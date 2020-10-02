(*
* Efimov V.P.
* kote.kagbe@gmail.com
* 2020
*)

unit blob_manager_unit;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
        Classes, SysUtils, FGL, Dialogs;

const
    MAX_BLOB_SIZE = 2*1024*1024*1024;

type
    tBlobList = specialize TFPGObjectList<tFileStream>;

	{ tBlobInfo }

    tBlobInfo = record
        pk,
        id,
        offset,
        size,
        ending: int64;
        class operator = ( aLeft, aRight: tBlobInfo ): boolean;
	end ;

    tBlobInfoList = specialize TFPGList<tBlobInfo>;

    tIntList = specialize TFPGList<int64>;

	{ tPKSizeRec }

    tPKSizeRec = record
        pk, size: int64;
        class operator = ( aLeft, aRight: tPKSizeRec ): boolean;
	end ;

    tPKSizeList = specialize TFPGList<tPKSizeRec>;

	{ tBlobManager }

    tBlobManager = class
    private
        _folder, _name: string;
        _manager: pointer;
        _blobs: tBlobList;
        _user_blob_table: string;
        _user_blob_pk: string;

        procedure FillBlobs;
        procedure InitializeDB;
    public
        constructor Create( const folder, name, blob_table, blob_pk: string; const manager: pointer );
        destructor Destroy; override;

        function Write( const strm: tStream; const id: word = 0; use_transaction: boolean = true ): word;
        procedure Read( const id: word; const strm: tStream );

        class function BlobTableName: string;
	end ;

implementation
uses sqlite_manager;

{ tPKSizeRec }

class operator tPKSizeRec. = ( aLeft, aRight: tPKSizeRec) : boolean;
begin
    result := aLeft.pk = aRight.pk;
end ;

{ tBlobInfo }

class operator tBlobInfo. = ( aLeft, aRight: tBlobInfo) : boolean;
begin
    result := aLeft.pk = aRight.pk;
end ;

{ tBlobManager }

procedure tBlobManager.FillBlobs;
var
    i: word;
begin
    i := 0;
    while FileExists( self._folder + self._name + '.blob.' + IntToStr( i ) ) do
        begin
            self._blobs.Add( TFileStream.Create( self._folder + self._name + '.blob.' + IntToStr( i ), fmOpenReadWrite ) );
            inc( i );
		end ;
	if self._blobs.Count < 1 then
        self._blobs.Add( TFileStream.Create( self._folder + self._name + '.blob.0', fmCreate ) );
end ;

procedure tBlobManager.InitializeDB;
var
    manager: tSQLiteManager;
begin
    manager := tSQLiteManager( self._manager );
    manager.Rollback;
    manager.Select( 'select count([rowid]) as [n] from [sqlite_master] where [type] = ''table'' and [name] in ( ''' + self.BlobTableName + ''', ''' + self._user_blob_table + ''' );' );
    manager.Next( true );
    if manager.FieldAsLongint( 'n' ) = 1 then //all converters are done and only user's table exists
        begin
            //check for user table existance
            manager.Select( 'select [rowid] from [sqlite_master] where [type] = ''table'' and [name] = ''' + self._user_blob_table + '''' );
            if not manager.Next( true ) then //user table not exists but system does - wrong
                raise Exception.Create( self._user_blob_table + ' table does not exist' );
            manager.Rollback;
            manager.StartTransaction;
            manager.Execute( 'create table [' + self.BlobTableName + '] ('
                             + '[id] integer primary key not null'
                             + ', [blob_id] integer not null'
                             + ', [blob_offset] integer not null'
                             + ', [blob_size] integer not null'
                             + ', [user_id] integer'
                             + ', [page] integer not null default -1'
                             + ', foreign key ([user_id]) references [' + self._user_blob_table + ']([' + self._user_blob_pk + ']) on update cascade on delete set null'
                             + ' )' );
            manager.Execute( 'create index [i_blob_info_user_id] on [' + self.BlobTableName + '] ( [id] ) where [user_id] is not null' );
            manager.Execute( 'create index [i_blob_info_deleted] on [' + self.BlobTableName + '] ( [id], [blob_id] ) where [user_id] is null' );
            manager.Commit;
		end
    else if manager.FieldAsLongint( 'n' ) = 2 then //both user's and system tables exist, let's check them
        begin
            try
                manager.Select( 'select [b].[id], [b].[blob_id], [b].[blob_offset], [b].[blob_size], [b].[user_id], [b].[page], [bi].[' + self._user_blob_pk + ']'
                               + ' from [' + self.BlobTableName + '] [b]'
                               + ' left join [' + self._user_blob_table + '] [bi] on [bi].[' + self._user_blob_pk + '] = [b].[user_id]'
                               + ' limit 1');
			except on e: Exception do
                raise Exception.Create( 'Wrong blob tables structure'#13 + e.Message );
			end ;
		end
    else
		raise Exception.Create( 'Wrong blob tables structure' );
    manager.Rollback;
end ;

constructor tBlobManager.Create( const folder, name, blob_table, blob_pk: string;
	const manager: pointer) ;
begin
    self._folder := folder;
    self._name := name;
    self._manager := manager;
    self._blobs := tBlobList.Create;
    self._user_blob_table := blob_table;
    self._user_blob_pk := blob_pk;
    try
        FillBlobs;
        InitializeDB;
	except on e: Exception do
        begin
            MessageDlg( 'Blob structure check failed'#13 + e.Message, mtError, [mbOk], 0 );
            halt;
		end ;
	end ;
end ;

destructor tBlobManager.Destroy;
begin
    self._blobs.Free;
	inherited Destroy;
end ;

function tBlobManager.Write( const strm: tStream; const id: word; use_transaction: boolean = true) : word;
var
    manager: tSQLiteManager;
    page: word;
    b: boolean;
    bytes_left: int64;
    blobs: tBlobInfoList;
    blob: tBlobInfo;
    written: int64;
    n: word;
    del_list: tIntList;
    pksize_list: tPKSizeList;
    pksize: tPKSizeRec;
    s: string;
    i: int64;
begin
    bytes_left := strm.Size;
    manager := tSQLiteManager( self._manager );
    if use_transaction then
        begin
		    manager.Rollback;
		    manager.StartTransaction;
		end ;
	try
	    if id = 0 then //new file
	        begin
	            manager.Execute( 'insert into [' + self._user_blob_table + '] default values' );
	            manager.Select( 'select last_insert_rowid() [id]' );
	            if not manager.Next( true ) then
	                raise Exception.Create( 'Failed to fetch new blob id' );
	            result := manager.FieldAsLongint( 'id' );
	            if result = 0 then
	                raise Exception.Create( 'Failed to insert new blob id' );
			end
	    else //existing file
	        begin
	            result := id;
                //file is beeing replaced, deleting old contents
	            manager.Execute( 'update [' + self.BlobTableName + '] set [user_id] = null where [user_id] = ' + IntToStr( id ) );
			end ;
		page := 0;
        strm.Seek( 0, soFromBeginning );
	    b := true;
        //if we have something existsting then let's replace it
	    manager.Select( 'select *, [blob_offset]+[blob_size] [blob_end] from [' + self.BlobTableName + '] where [user_id] is null order by [blob_id], [blob_offset]' );
        blobs := tBlobInfoList.Create;
        del_list := tIntList.Create;
        pksize_list := tPKSizeList.Create;
	    while manager.Next( b ) do
	        begin
	            b := false;
                if ( blobs.Count > 0 ) //we can merge several sequent chunks
                   and ( blobs[blobs.Count-1].ending = manager.FieldAsLongint( 'blob_offset' ) )
                   and ( blobs[blobs.Count-1].id = manager.FieldAsLongint( 'blob_id' ) ) then
                    begin
                        blob := blobs[blobs.Count-1];
                        blob.ending += manager.FieldAsLongint( 'blob_size' );
                        blob.size += manager.FieldAsLongint( 'blob_size' );
                        blobs[blobs.Count-1] := blob;
                        //current chunk-tail must be deleted
                        del_list.Add( manager.FieldAsLongint( 'id' ) );
                        //merged chunk must have new size
                        pksize.pk := blob.pk;
                        pksize.size := blob.size;
                        i := pksize_list.IndexOf( pksize );
                        if i > -1 then
                            pksize_list[i] := pksize
                        else
                            pksize_list.Add( pksize );
                    end
                else
                    begin
		                blob.pk := manager.FieldAsLongint( 'id' );
		                blob.offset := manager.FieldAsLongint( 'blob_offset' );
		                blob.size := manager.FieldAsLongint( 'blob_size' );
		                blob.id := manager.FieldAsLongint( 'blob_id' );
		                blob.ending := manager.FieldAsLongint( 'blob_end' );
		                blobs.Add( blob );
                    end;
			end ;
        if del_list.Count > 0 then
            begin
                s := '0';
                for n in del_list do
                    s += ','+IntToStr(n);
                manager.Execute( 'delete from [' + BlobTableName + '] where [id] in (' + s + ')' );
			end ;
        if pksize_list.Count > 0 then
            for n := 0 to pksize_list.Count - 1 do
                manager.Execute( 'update [' + BlobTableName + '] set [blob_size] = ' + inttostr( pksize_list[n].size ) + ' where [id] = ' + inttostr( pksize_list[n].pk ) );
		del_list.Free;
        pksize_list.Free;
        page := 0;
        for blob in blobs do
            begin
                if blob.size <= bytes_left then //small chunk, write it full
                    begin
                        self._blobs[blob.id].Seek( blob.offset, soFromBeginning );
                        written := self._blobs[blob.id].CopyFrom( strm, blob.size );
                        if written < blob.size then
                            raise Exception.Create( 'Couldn''t write the whole chunk' );
                        manager.Execute( 'update [' + BlobTableName + '] set'
                                         + ' [user_id] = ' + IntToStr( result )
                                         + ', [page] = ' + IntToStr( page )
                                         + ' where [id] = ' + IntToStr( blob.pk ) );
					end
                else //chunk is bigger, replacing it partly and naming left space as new blob
                    begin
                        self._blobs[blob.id].Seek( blob.offset, soFromBeginning );
                        written := self._blobs[blob.id].CopyFrom( strm, bytes_left );
                        if written < bytes_left then
                            raise Exception.Create( 'Couldn''t write the chunk partly' );
                        manager.Execute( 'update [' + BlobTableName + '] set'
                                         + ' [user_id] = ' + IntToStr( result )
                                         + ', [page] = ' + IntToStr( page )
                                         + ', [blob_size] = ' + IntToStr( written )
                                         + ' where [id] = ' + IntToStr( blob.pk ) );
                        manager.Execute( 'insert into [' + BlobTableName + '] ( [blob_id], [blob_offset], [blob_size] )'
                                         + ' values ( '
                                         + IntToStr( blob.id )
                                         + ', ' + inttostr( self._blobs[blob.id].Position )
                                         + ', ' + inttostr( blob.size - written )
                                         + ' )' );
					end ;
                inc( page );
                bytes_left := bytes_left - written;
                if bytes_left < 1 then
                    break;
			end ;
		blobs.Free;
        //if something remains to be written then let's make new records
        while bytes_left > 0 do
            begin
                blob.id := -1;
                for n := 0 to self._blobs.Count - 1 do
                    if self._blobs[n].Size < MAX_BLOB_SIZE then
                        begin
                            blob.id := n;
                            break;
						end ;
                if blob.id < 0 then
                    begin
                        blob.id := self._blobs.Count;
                        self._blobs.Add( TFileStream.Create( self._folder + self._name + '.blob.' + IntToStr( self._blobs.Count ), fmCreate ) );
					end ;
                manager.Select( 'select max([blob_offset]), coalesce( [blob_size]+[blob_offset], 0 ) [blob_end] from [' + BlobTableName + '] where [blob_id] = ' + inttostr( blob.id ) );
                manager.Next( true );
                self._blobs[blob.id].Seek( manager.FieldAsLongint( 'blob_end' ), soFromBeginning );
                blob.offset := self._blobs[blob.id].Position;
                blob.size := MAX_BLOB_SIZE - self._blobs[blob.id].Size; //free space in current blob
                if blob.size > bytes_left then //if free space larger than data to write
                    blob.size := bytes_left; //then write only data
                written := self._blobs[blob.id].CopyFrom( strm, blob.size );
                if written < blob.size then
                    raise Exception.Create( 'Couldn''t write the chunk tail' );
                manager.Execute( 'insert into [' + BlobTableName + '] ( [blob_id], [blob_offset], [blob_size], [user_id], [page] )'
                                 + ' values ( '
                                 + IntToStr( blob.id )
                                 + ', ' + inttostr( blob.offset )
                                 + ', ' + inttostr( blob.size )
                                 + ', ' + inttostr( result )
                                 + ', ' + inttostr( page )
                                 + ' )' );
                bytes_left := bytes_left - written;
                inc( page );
			end ;
        if use_transaction then
    		manager.Commit;
	except
        if use_transaction then
            manager.Rollback;
        //if we wrote into blob something before it crashed then the old file is broken and must be removed
        if ( strm.Position > 0 ) and ( id > 0 ) then
            manager.Execute( 'delete from [' + self._user_blob_table + '] where [' + self._user_blob_pk + '] = ' + IntToStr( id ), use_transaction );
        raise;
	end ;
end ;

procedure tBlobManager.Read( const id: word; const strm: tStream) ;
var
    manager: tSQLiteManager;
    b: boolean;
begin
    manager := tSQLiteManager( self._manager );
    //manager.Rollback; //??????
    manager.Select( 'select * from [' + BlobTableName + '] where [user_id] = ' + inttostr( id ) + ' order by [page]' );
    b := true;
    while manager.Next( b ) do
        begin
            b := false;
            self._blobs[manager.FieldAsLongint( 'blob_id' )].Seek( manager.FieldAsLongint( 'blob_offset' ), soFromBeginning );
            strm.CopyFrom( self._blobs[manager.FieldAsLongint( 'blob_id' )], manager.FieldAsLongint( 'blob_size' ) );
		end ;
end ;

class function tBlobManager.BlobTableName: string;
begin
    result := 'blob_info';
end ;



end .

