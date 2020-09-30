unit base_updater;

{$mode objfpc}{$H+}

interface

uses
    Classes, SysUtils, fgl, md5, Zipper, FileUtil, md5_stream, strutils;

const
    EMPTY_HASH = '00000000000000000000000000000000';
    HASHES_LIST_FILE = 'hashes.list';

type
    tUpdaterAction = ( tuaCHECK, tuaUPDATE );
    tUpdaterResult = ( turUPTODATE, turHASUPDATES, turUPDATED, turUPDATEERROR, turNETWORKERROR );
    tFileUpdateAction = ( tfuaNONE, tfuaADD, tfuaREMOVE, tfuaREWRITE );

    { tFileUpdateData }

    tFileUpdateData = class
    public
        path: string;
        old_hash, new_hash: string;
        action: tFileUpdateAction;
        size: int64; //new file size

        constructor Create( fpath, hash: string; fsize: int64 = 0 );
        function Changed: boolean;
	end ;

    tFileUpdateList = specialize TFPGObjectList<tFileUpdateData>;

    //on turHASUPDATES and get_update_size = true n contains total files size
    //on turUPDATED n and m contains parts of hash.list md5, external app must save it and set when checking updates
    tStatusCallback = procedure( Sender: TObject; status: tUpdaterResult; n, m: int64 ) of object;
    tFileDownloadCallback = procedure( Sender: TObject; fname: string; n: int64 );
    tFileApplyCallback = procedure( Sender: TObject; fname: string; n: int64 );

	{ tProxyData }

    tProxyData = record
        server,
        port,
        user,
        password: string;
	end ;

    tUserData = record
        int64_field: int64;
        string_field: string;
        float_field: double;
        pointer_field: pointer;
	end ;

	{ tBaseUpdater }

    tBaseUpdater = class( TThread )
        protected
            _action: tUpdaterAction;
            _working_folder: string;
            _files: tFileUpdateList;
            _hashes: tStringList;
            _old_hash: string;
            _user_data: tUserData;
            _proxy: tProxyData;
            _temp_folder: string;
            _mask: string;
            _recursive: boolean;
            _direct_mode: boolean;
            _get_update_size: boolean;
            _backup: boolean;
            _log: TFileStream;
            _total_size: int64;
            _source: string;

            _on_status: tStatusCallback;
            _on_file_download: tFileDownloadCallback;
            _on_file_apply: tFileApplyCallback;

            function CheckUpdates: boolean; virtual;
            function ApplyUpdates: boolean; virtual;
            function FetchFile( rel_name: string ): boolean; virtual; abstract;
            function ApplyFile( rel_name: string ): boolean; virtual;
            function CheckFiles: boolean;
            function ReleaseFile( full_name: string ): boolean;
            procedure Backup;
            procedure log( msg: string );
            procedure report( const msg: tUpdaterResult; n: int64 = 0; m: int64 = 0 );

            procedure Execute; override;
        public
            constructor Create( working_folder: string; action: tUpdaterAction; auto_release: boolean = true );
            destructor Destroy; override;

            procedure SetCurrentHash( n, m: int64 );

            property temp_folder: string read _temp_folder write _temp_folder;
            property mask: string read _mask write _mask;
            property recursive: boolean read _recursive write _recursive;
            property direct_download: boolean read _direct_mode write _direct_mode;
            property get_updates_size: boolean read _get_update_size write _get_update_size;
            property need_backup: boolean read _backup write _backup;
            property proxy: tProxyData read _proxy;
            property user_data: tUserData read _user_data;
            property source: string read _source write _source;

            property onStatus: tStatusCallback write _on_status;
            property onDownload: tFileDownloadCallback write _on_file_download;
            property onApply: tFileApplyCallback write _on_file_apply;
	end ;

implementation

{ tBaseUpdater }

function tBaseUpdater.CheckUpdates: boolean;
begin
    FetchFile( HASHES_LIST_FILE );
    if( _old_hash <> EMPTY_HASH )and( not _get_update_size )then
        result := _old_hash <> MD5Print( MD5String( _hashes.Text ) )
    else
        result := CheckFiles;
end ;

function tBaseUpdater.ApplyUpdates: boolean;
var
    fud: tFileUpdateData;
begin
    if not CheckUpdates then
        begin
            if _on_status <> nil then _on_status( self, turUPTODATE, 0, 0 );
            exit( false );
		end ;
	if _direct_mode and _backup then
        Backup;
    for fud in _files do
        if fud.action in [tfuaADD, tfuaREWRITE] then
            FetchFile( fud.path );
    if not _direct_mode and _backup then
        Backup;
    if not _direct_mode then
	    for fud in _files do
	        begin
	            if fud.action in [tfuaADD, tfuaREWRITE] then
	                ApplyFile( fud.path );
			end ;
end ;

function tBaseUpdater.ApplyFile( rel_name: string ): boolean;
const
    COPY_CHUNK_SIZE = 10*1024*1024;
var
    dst_strm, src_strm: TFileStream;
    n: int64;
    dst: string;
begin
    if _direct_mode then exit;
    log( 'applying file ' + rel_name );
    dst := ExtractFilePath( _working_folder + rel_name );
    if not DirectoryExists( dst ) then
	    if not ForceDirectories( dst ) then
	        log( 'couldn''t create directory ' + dst );
    ReleaseFile( _working_folder + rel_name );
    src_strm := TFileStream.Create( _temp_folder + rel_name, fmOpenRead );
    dst_strm := TFileStream.Create( _working_folder + rel_name, fmCreate );
    n := 0;
    repeat
        n := dst_strm.CopyFrom( src_strm, COPY_CHUNK_SIZE );
        if Assigned( _on_file_apply )then
            _on_file_apply( self, rel_name, src_strm.Position );
	until n < COPY_CHUNK_SIZE;
	src_strm.Free;
    dst_strm.Free;
    result := true;
end ;

function tBaseUpdater.CheckFiles: boolean;
const
    delim = ['|'];
var
    local: tStringList;
    line, name, hash: string;
    strm: TFileStream;
    n: integer;
    size: int64;
    fud: tFileUpdateData;
begin
    log( 'building update list' );
    _files.Clear;
    for line in _hashes do
        begin
            if( pos( '|', line ) = 0 )or( WordCount( line, delim ) <> 3 )then
                begin
                    log( 'wrong hash line ' + line );
                    Continue;
				end ;
            name := ExtractDelimited( 1, line, delim );
            hash := ExtractDelimited( 2, line, delim );
            size := StrToInt64( ExtractDelimited( 3, line, delim ) );
            _files.Add( tFileUpdateData.Create( name, hash, size ) );
		end ;
    log( 'collecting local files' );
    local := FindAllFiles( _working_folder, _mask, _recursive );
    log( 'parsing local files' );
    for line in local do
        begin
            name := line.Substring( length( _working_folder ) );
            log( name );
            strm := TFileStream.Create( line, fmOpenRead );
            hash := MD5Print( MD5Stream( strm ) );
            strm.Free;
            n := -1;
            if _files.Count > 0 then
                for fud in _files do
                    begin
                        n += 1;
                        if fud.path = name then
                            break;
                    end;
            if n > -1 then
                _files[n].old_hash := hash
            else
                begin
                    fud := tFileUpdateData.Create( name, EMPTY_HASH );
                    fud.old_hash := hash;
                    _files.Add( fud );
				end ;
		end ;
    log( 'analyzing' );
    result := false;
    _total_size := 0;
    for fud in _files do
        if fud.Changed then
            begin
                result := true;
                if fud.old_hash = EMPTY_HASH then
                    begin
                        log( fud.path + ' will be added' );
                        _total_size += fud.size;
                        fud.action := tfuaADD;
					end
                else if fud.new_hash = EMPTY_HASH then
                    begin
                        log( fud.path + ' will be removed' );
                        fud.action := tfuaREMOVE
					end
				else
                    begin
                        log( fud.path + ' will be rewritten' );
                        _total_size += fud.size;
                        fud.action := tfuaREWRITE;
					end ;
			end
        else
            log( fud.path + ' has not changed' );
end ;

function tBaseUpdater.ReleaseFile( full_name: string ): boolean;
var
    attr: longint;
begin
    result := true;
    if not FileExists( full_name ) then exit;
    log( 'releasing file ' + full_name );
    attr := FileGetAttr( full_name );
    if ( attr <> -1 )and( ( attr and faReadOnly ) <> 0 ) then
        if FileSetAttr( full_name, attr - faReadOnly ) < 0 then
            log( 'couldn''t remove RO attribute' );
    if not DeleteFile( full_name ) then
        begin
            log( 'couldn''t delete file ' );
            if not RenameFile( full_name, full_name + '.old' ) then
                begin
                    log( 'couldn''t rename file ' );
                    result := false;
				end ;
		end ;
end ;

procedure tBaseUpdater.Backup;
var
    zip: TZipper;
    fud: tFileUpdateData;
begin
    zip := TZipper.Create;
    zip.FileName := _working_folder + FormatDateTime( 'ddmmyyyy_hhnnss', Now ) + '.zip';
    for fud in _files do
        if fud.action in [tfuaREMOVE, tfuaREWRITE] then
            zip.Entries.AddFileEntry( _working_folder + fud.path, fud.path );
    try
        zip.ZipAllFiles;
	finally
        zip.Free;
	end ;
end ;

procedure tBaseUpdater.log( msg: string) ;
var
    txt: string;
begin
    if not Assigned( _log ) then exit;
    txt := '';
    if not msg.IsEmpty then
        txt := FormatDateTime( 'hh:nn:ss.zzz', now ) + ' ' + msg;
    txt += #13;
    _log.Write( txt[1], length( txt ) );
end ;

procedure tBaseUpdater.report( const msg: tUpdaterResult; n: int64; m: int64) ;
begin
    if Assigned( _on_status ) then
        _on_status( self, msg, n, m );
end ;

procedure tBaseUpdater.Execute;
begin
    log( 'STARTED' );
    try
        case _action of
            tuaCHECK: CheckUpdates;
            tuaUPDATE: ApplyUpdates;
		end ;
	except on e: Exception do
	    begin
            log( 'ERROR=' + e.Message );
            report( turUPDATEERROR );
		end ;
	end ;
    log( 'FINISHED' );
	Terminate;
end ;

constructor tBaseUpdater.Create( working_folder: string;
	action: tUpdaterAction; auto_release: boolean) ;
var
    guid: TGuid;
begin
    inherited Create( true );
    FreeOnTerminate := auto_release;
    _action := action;
    _working_folder := working_folder;
    if not _working_folder.EndsWith( PathDelim ) then _working_folder += PathDelim;
    if ( _working_folder.IsEmpty )or( not ForceDirectories( _working_folder ) ) then
        raise Exception.Create( 'working folder is not specified' );
    try
        _log := TFileStream.Create( _working_folder + 'updater.log', fmCreate );
	except on e: Exception do
        begin
            if _action = tuaUPDATE then
                raise Exception.Create( _working_folder + ' is being updated or write protected'#13 + e.Message )
            else
                _log := nil;
		end ;
	end ;

    _files := tFileUpdateList.Create;
    _hashes := TStringList.Create;
    _old_hash := EMPTY_HASH;
    _temp_folder := GetTempDir;
    if not _temp_folder.EndsWith( PathDelim ) then _temp_folder += PathDelim;
    CreateGUID( guid );
    _temp_folder += GUIDToString( guid ) + PathDelim;
    ForceDirectories( _temp_folder );
    _mask := '*.*';
    _recursive := false;
    _direct_mode := false;
    _get_update_size := false;
    _backup := true;
end ;

destructor tBaseUpdater.Destroy;
begin
	inherited Destroy;
    if Assigned( _files ) then _files.Free;
    if Assigned( _log ) then _log.Free;
    if Assigned( _hashes ) then _hashes.Free;
end ;

procedure tBaseUpdater.SetCurrentHash( n, m: int64) ;
var
    d: TMD5Digest;
begin
    move( n, d, 8 );
    move( m, d[8], 8 );
    _old_hash := MD5Print( d );
end ;

{ tFileUpdateData }

constructor tFileUpdateData.Create( fpath, hash: string; fsize: int64) ;
begin
    path := fpath;
    new_hash := hash;
    old_hash := EMPTY_HASH;
    size := fsize;
    action := tfuaNONE;
end ;

function tFileUpdateData.Changed: boolean;
begin
    result := old_hash <> new_hash;
end ;

end .

