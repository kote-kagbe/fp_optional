(*
* Efimov V.P.
* kote.kagbe@gmail.com
* 2020
*)

unit database_converter_unit;

{$mode objfpc}{$H+}

interface

uses
        Classes, SysUtils, FGL, strutils, md5;

type
    tMetaSaver = specialize TFPGMap<string, tStrings>;

	{ tDatabaseConverter }

    tDatabaseConverter = class
    private
        _folder, _name: string;
        _manager: pointer;
        _log: tStrings;
        instructions: tStrings;
        indexes: tMetaSaver;
        triggers: tMetaSaver;

        procedure Prepare;
        procedure Log( txt: string );
        function ProcessConverter( const path: string ): boolean;
        procedure ClearSavedMeta;
        function SubVersion: word;
    public
        constructor Create( const folder, name: string; use_log: boolean; const manager: pointer );
        destructor Destroy; override;

        procedure Run;
        function Version: word;
        function NeedConvertation: boolean;
	end ;

implementation
uses sqlite_manager;
{ tDatabaseConverter }

procedure tDatabaseConverter.Prepare;
var
    manager: tSQLiteManager;
begin
    manager := tSQLiteManager( self._manager );
    manager.Select( 'select count(1) "cnt" from [sqlite_master] where [type] = ''table'' and [name] in ( ''metadata'', ''converters'' );' );
    if manager.FieldAsLongint( 'cnt' ) = 0 then
        with manager do begin
            Rollback;
            StartTransaction;
            Execute( 'create table [metadata] ( [key] text not null, [value] text );' );
            Execute( 'create unique index [i_metadata_u_key] on [metadata] ( [key] );' );
            Execute( 'insert into [metadata] ( [key], [value] ) values ( ''version'', 0 ), ( ''subversion'', 0 );' );
            Execute( 'create table [converters] ( [name] text not null, [hash] text not null, [applied] real not null default ( julianday( ''now'' ) ) );' );
            Execute( 'create unique index [i_converters_hash] on [converters] ( [name], [hash] );' );
            Commit;
		end
    else if manager.FieldAsLongint( 'cnt' ) <> 2 then
        raise Exception.Create( 'Database service structures are corrupted' );
end ;

procedure tDatabaseConverter.Log( txt: string) ;
begin
    if Assigned( self._log ) then
        self._log.Add( txt );
end ;

function tDatabaseConverter.ProcessConverter( const path: string) : boolean;
var
    line, query, tname, fname: string;
    n: word;
    manager: tSQLiteManager;
    b, fk: boolean;
    hash, tmp: string;
    v: integer;
begin
    log( 'running converter ' + path );
    manager := tSQLiteManager( self._manager );
    hash := MD5Print( MD5File( path ) );
    fname := ExtractFileName( path );
    manager.Select( 'select [rowid] from [converters] where [hash] = ''' + hash + ''' and [name] = ''' + fname + '''' );
    if manager.Next( true ) then
        raise Exception.Create( 'Converter ' + fname + ' has been applied already' )
    else
        manager.Rollback;
    ClearSavedMeta;
    instructions.Clear;
    instructions.LoadFromFile( path );
    n := 0;
    query := '';
    fk := false;
    try
        manager.StartTransaction;
        for line in instructions do
            begin
                if line <> '' then
                    begin
	                    if line.StartsWith( '--' ) then
	                        continue;
	                    if ( query = '' ) and ( line[1] = '@' ) then
	                        begin
	                            case ExtractDelimited( 1, line, [' '] ) of
	                            '@save_indexes': begin
	                                log( 'instruction ' + inttostr( n ) );
	                                tname := ExtractDelimited( 2, line, [' '] );
                                    if tname.IsEmpty then
                                        raise Exception.Create( '@save_index table name is empty' );
		                            manager.Select( 'select [sql] from [sqlite_master] where [type] = ''index'' and [tbl_name] = ''' + tname + ''';' );
		                            if indexes.IndexOf( tname ) < 0 then
		                                indexes.Add( tname, tStringList.Create );
		                            b := true;
		                            while manager.Next( b ) do
		                                begin
		                                    b := false;
		                                    indexes[tname].Add( manager.FieldAsString( 'sql' ) );
										end ;
		                            log( 'saved ' + inttostr( indexes[tname].Count ) + ' indexes for table ' + tname );
								end ;
		                        '@restore_indexes': begin
		                            log( 'instruction ' + inttostr( n ) );
		                            tname := ExtractDelimited( 2, line, [' '] );
                                    if tname.IsEmpty then
                                        raise Exception.Create( '@restore_indexes table name is empty' );
		                            if indexes.IndexOf( tname ) < 0 then
		                                log( 'indexes for table ' + tname + ' not found' )
		                            else
		                                begin
		                                    for query in indexes[tname] do
		                                        manager.Execute( query );
		                                    log( 'restored ' + inttostr( indexes[tname].Count ) + ' indexes for table ' + tname );
		                                    query := '';
								        end ;
								end;
                                '@save_triggers': begin
	                                log( 'instruction ' + inttostr( n ) );
	                                tname := ExtractDelimited( 2, line, [' '] );
                                    if tname.IsEmpty then
                                        raise Exception.Create( '@save_triggers table name is empty' );
		                            manager.Select( 'select [sql] from [sqlite_master] where [type] = ''trigger'' and [tbl_name] = ''' + tname + ''';' );
		                            if triggers.IndexOf( tname ) < 0 then
		                                triggers.Add( tname, tStringList.Create );
		                            b := true;
		                            while manager.Next( b ) do
		                                begin
		                                    b := false;
		                                    triggers[tname].Add( manager.FieldAsString( 'sql' ) );
										end ;
		                            log( 'saved ' + inttostr( triggers[tname].Count ) + ' triggers for table ' + tname );
								end ;
		                        '@restore_triggers': begin
		                            log( 'instruction ' + inttostr( n ) );
		                            tname := ExtractDelimited( 2, line, [' '] );
                                    if tname.IsEmpty then
                                        raise Exception.Create( '@restore_triggers table name is empty' );
		                            if triggers.IndexOf( tname ) < 0 then
		                                log( 'triggers for table ' + tname + ' not found' )
		                            else
		                                begin
		                                    for query in triggers[tname] do
		                                        manager.Execute( query );
		                                    log( 'restored ' + inttostr( triggers[tname].Count ) + ' triggers for table ' + tname );
		                                    query := '';
								        end ;
								end;
                                '@disable_foreign_keys': begin
                                    log( 'instruction ' + inttostr( n ) );
                                    if n <> 0 then
                                        raise Exception.Create( '@disable_foreign_keys must be the first instruction' );
                                    fk := true;
                                    manager.ForeignKeys( false ); //reopens DB, need new transaction
                                    manager.StartTransaction;
								end;
                                '@set_version', '@set_subversion': begin
                                    log( 'instruction ' + inttostr( n ) );
                                    v := StrToIntDef( ExtractDelimited( 2, line, [' '] ), -1 );
                                    if v < 0 then
                                        raise Exception.Create( line + ' value must be integer >=0' );
                                    tmp := ExtractDelimited( 2, line, ['_',' '] );
                                    manager.ClearParams;
                                    manager.SetParam( 'value', v );
                                    manager.SetParam( 'key', tmp );
                                    manager.Execute( 'replace into [metadata] ( [key], [value] ) values ( :key, :value )' );
								end
								else
		                            raise Exception.Create( 'unknown instruction ' + line );
							    end ;
		                        inc( n );
	                        end
	                    else
	                        query := query + line + #10;
					end
                else if query <> '' then
                    begin
                        log( 'instruction ' + inttostr( n ) );
                        manager.Execute( query );
                        query := '';
                        inc( n );
				    end ;
		    end ;
        if fk then
            begin
                manager.Select( 'pragma foreign_key_check' );
                if manager.Next( true ) then
                    raise Exception.Create( 'Post-converter foreign key check failed!' );
                manager.Commit;
                manager.ForeignKeys( true );
            end
        else
            manager.Commit;
        manager.Execute( 'insert into [converters] ( [name], [hash] ) values ( ''' + fname + ''', ''' + hash + ''' )', true );
        result := true;
    except on e: Exception do
        begin
            log( 'converter raised exception: ' + e.Message );
	        manager.Rollback;
	        result := false;
        end;
    end;
end ;

procedure tDatabaseConverter.ClearSavedMeta;
var
    i: word;
begin
    if indexes.Count > 0 then
        for i := 0 to indexes.Count - 1 do
            indexes.Data[i].Free;
    if triggers.Count > 0 then
        for i := 0 to triggers.Count - 1 do
            triggers.Data[i].Free;
end ;

constructor tDatabaseConverter.Create( const folder, name: string; use_log: boolean; const manager: pointer ) ;
begin
    _folder := folder;
    _name := name;
    _manager := manager;
    indexes := tMetaSaver.Create;
    indexes.Sorted := true;
    indexes.Duplicates := dupError;
    triggers := tMetaSaver.Create;
    triggers.Sorted := true;
    triggers.Duplicates := dupError;
    if use_log then
        _log := tStringList.Create;
    Prepare;
end ;

destructor tDatabaseConverter.Destroy;
begin
    if Assigned( self._log ) then
        begin
            self._log.SaveToFile( self._folder + self._name + '.converter.log' );
            self._log.Free;
		end ;
    ClearSavedMeta;
    indexes.Free;
    triggers.Free;
	inherited Destroy;
end ;

procedure tDatabaseConverter.Run;
var
    ver, sver: string;
    next: boolean;
begin
    ver := IntToStr( Version );
    sver := IntToStr( SubVersion );
    log( 'current version is ' + ver );
    log( 'current subversion is ' + sver );
    next := true;
    instructions := tStringList.Create;
    while next do
        begin
            //when ver is 0, then the db has not been initialized and subconverters are not allowed
            //the first converter must change version to 1 and only then the subconverters go
            if ( ver <> '0' ) and FileExists( self._folder + self._name + '.' + ver + '.' + sver + '.sqmcnv.sql' ) then
                next := ProcessConverter( self._folder + self._name + '.' + ver + '.' + sver + '.sqmcnv.sql' )
            else if FileExists( self._folder + self._name + '.' + ver + '.sqmcnv.sql' ) then
                next := ProcessConverter( self._folder + self._name + '.' + ver + '.sqmcnv.sql' )
            else
                next := false;
            ver := IntToStr( Version );
            sver := IntToStr( SubVersion );
            log( 'intermediate version is ' + ver + ' and subversion is ' + sver );
		end ;
    instructions.Free;
    log( 'finalized with version ' + inttostr( Version ) + ' and subversion ' + inttostr( SubVersion ) );
end ;

function tDatabaseConverter.NeedConvertation: boolean;
var
    ver: string;
begin
    ver := IntToStr( Version );
    result := FileExists( self._folder + self._name + '.' + ver + '.sqmcnv.sql' )
              or FileExists( self._folder + self._name + '.' + ver + '.' + IntToStr( SubVersion ) + '.sqmcnv.sql' );
end ;

function tDatabaseConverter.Version: word;
var
    manager: tSQLiteManager;
begin
    manager := tSQLiteManager( _manager );
    manager.Select( 'select coalesce( [value], 0 ) as [version] from [metadata] where [key] = ''version'';' );
    if manager.Next( true ) then
        result := word( manager.FieldAsLongint( 'version' ) )
    else
        result := 0;
    manager.Rollback;
end ;

function tDatabaseConverter.SubVersion: word;
var
    manager: tSQLiteManager;
begin
    manager := tSQLiteManager( _manager );
    manager.Select( 'select coalesce( [value], 0 ) as [subversion] from [metadata] where [key] = ''subversion'';' );
    if manager.Next( true ) then
        result := word( manager.FieldAsLongint( 'subversion' ) )
    else
        result := 0;
    manager.Rollback;
end ;

end .

