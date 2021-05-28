unit base_updater;

(*
syntax notes
- class variables start with _
    _my_protected_or_private_var: supertype;
- service methods like logging etc. start and end with __
    __log__( 'mymessage' );
- constants are in upper case
    VERY_CONSTANT_VALUE = 666;
- macroses are in upper case, outer macroses start and end with __, inner macroses start and end with _
    __START_MACROS_ with some code _CONTINUE_MACROS_ with more code _END_MACROS__
- macros should end with semicolon
    {$define __MY_MACRO__:=begin result:=false; __log__( 'oops!' ); break; end;}
    ...some loop
        ...some code
        if something_happened then
            __MY_MACRO__
    ...after loop code
*)

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$macro on}
{$inline on}
{$warn 6058 off} // suppressing "Call to subroutine "blah.blah" marked as inline is not inlined"

interface

uses sysutils, classes, fgl, fileutil, md5, math,
     scope_container, md5_stream;

const
    OLD_FILE_EXT = '.old';
    DEFAULT_STORAGE_NAME = 'updates' + DirectorySeparator;
    FILE_OPERATION_CHUNK_SIZE = 1024*1024;

type
    // log message types
    tLogMessageType = ( lmtMESSAGE, lmtWARNING, lmtERROR );
    // custom log functions
    tLogProcessor = procedure( const message_text: string; const message_type: tLogMessageType = lmtMESSAGE );
    tStreamLogProcessor = procedure( const data: tStream; const message_type: tLogMessageType = lmtMESSAGE );
    // operations result
    tCheckResult = ( crUPTODATE, crOUTDATED, crABORTED, crERROR );
    tFetchResult = ( frOK, frABORTED, frERROR );
    tApplyResult = ( arOK, arABORTED, arPARTIAL, arERROR );
    // custom file handling
    // called on start updating each changed file
    // file_name is the relative path
    // if returns false then standart handling applyed
    // when using packaging, i.e. zip-distribution, one shall fill right _map.hashes in FetchRemoteFilesInfo to switch off standart logic
    tCustomFileProcessor = function( const file_name: string; const source: tStream ): boolean;
    // operation status for progress callback
    tUpdateStatus = ( usIDLE, usCLEANUP, usCHECKING_LOCAL, usCHECKING_STORAGE, usCHECKING_REMOTE, usFETCHING, usUPDATING, usREVERTING );
    // percentage of progress
    // -1 means unknown
    tUpdateProgress = -1..100;
    // progress indication callback
    tProgressCallback = procedure( const path: string; const status: tUpdateStatus; const progress_current, progress_total: tUpdateProgress );

    tUpdaterOptions = record
        source: string; // source address
        destination: string; // destination folder
        storage: string; // temporary folder to store updates
        mask: string; // list of file masks to work with
        skip_apply_errors: boolean; // when true and ApplyFile fails then ApplyUpdates doesn't stop and arPARTIAL will be returned
        distribution: string; // packed new files, requires assigned custom_file_processor. When set custom_file_processor shall unpack new files into .storage then FetchStorageFilesInfo will be called
        custom_file_processor: tCustomFileProcessor;
        progress_callback: tProgressCallback;
        log_processor: tLogProcessor;
        stream_log_processor: tStreamLogProcessor;
    private
        procedure Prepare;
        function Summary: string;
        class operator initialize( var instance: tUpdaterOptions ); inline;
    end;

    tFileRecord = record
        local_hash: string;
        remote_hash: string;
        storage_hash: string;
        remote_path: string;
        size: int64;
    function NeedUpdate: boolean;
    function Added: boolean;
    function Removed: boolean;
    function Stored: boolean;
    end;

    tFileList = specialize tFPGMap<string,tFileRecord>;

    tBaseUpdater = class
    private
        _aborted: boolean;
        _id: string; // id for each instance
        // options for current updater
        _options: tUpdaterOptions;

        // fill entire _map
        function FillMap: boolean;
        procedure FetchStorageFilesInfo;
    protected
        // merged list of files hashes <rel_path, tFileRecord>
        _map: tFileList;

        // fills _map with remote data: options.source -> _map[, _map.remote_path]
        function FetchRemoteFilesInfo: boolean; virtual; abstract;
        // fills _map with local data: options.destination -> _map
        function FetchLocalFilesInfo: boolean; virtual;
        // fetches single remote file to local machine: options.source -> options.storage
        function FetchFile( const path: string; const destination: tStream ): boolean; virtual; abstract;
        // replaces single local file with updated one: options.storage -> options.destination
        function ApplyFile( const path: string; const source, destination: tStream ): boolean; virtual;

        // service methods
        procedure __report__( const path: string; const status: tUpdateStatus; const progress_current: tUpdateProgress; const progress_total: tUpdateProgress = -1 ); inline;
        function __percent__( const current, total: word ): tUpdateProgress; inline;
        procedure __log__( const message_text: string; const message_type: tLogMessageType = lmtMESSAGE ); inline;

        procedure log_file_map;

        property aborted: boolean read _aborted;
        property instance_id: string read _id;
        property options: tUpdaterOptions read _options;
    public
        constructor Create( const updater_options: tUpdaterOptions ); virtual; 
        destructor Destroy; override;

        function CheckUpdates: tCheckResult;
        function FetchUpdates: tFetchResult;
        function ApplyUpdates: tApplyResult;
        function RevertUpdates: boolean;

        // aborts any action
        procedure Abort;
        // removes *.old files and .storage
        function CleanUp( all: boolean = true ): boolean;
    end;

implementation

{$define LOOP_MACRO}
{$include updater_macro}

class operator tUpdaterOptions.initialize( var instance: tUpdaterOptions );
begin
    instance.custom_file_processor := default( tCustomFileProcessor );
    instance.progress_callback := default( tProgressCallback );
    instance.log_processor := default( tLogProcessor );
    instance.skip_apply_errors := false;
end;

procedure tUpdaterOptions.Prepare;
begin
    if self.source.IsEmpty then
        raise Exception.Create( 'Source path is not set' );

    if self.destination.IsEmpty then
        raise Exception.Create( 'Destination path is not set' );
    if not self.destination.EndsWith( DirectorySeparator ) then
        self.destination += DirectorySeparator;
    if not DirectoryExists( self.destination ) then
        if not ForceDirectories( self.destination ) then
            raise Exception.Create( 'Destination path does not exist' );

    if self.storage.IsEmpty then
        self.storage := self.destination + DEFAULT_STORAGE_NAME;
    if not self.storage.EndsWith( DirectorySeparator ) then
        self.storage += DirectorySeparator;
    if not DirectoryExists( self.storage ) then
        if not ForceDirectories( self.storage ) then
            raise Exception.Create( 'Storage path does not exist' );

    if( not self.distribution.IsEmpty )and( not assigned( self.custom_file_processor ) )then
        raise Exception.Create( 'When using distribution the custom file processor should be set' );

    if self.mask.IsEmpty then
        self.mask := '*';
end;

function tUpdaterOptions.Summary: string;
    function assigned_as_string( const ptr: Pointer ): string;
    begin
        if assigned( ptr ) then
            result := 'true' + LineEnding
        else
            result := 'false' + LineEnding;
    end;
    function boolean_as_string( const b:boolean ):string;
    begin
        if b then
            result := 'true' + LineEnding
        else
            result := 'false' + LineEnding;
    end;
begin
    result := LineEnding
    + 'source:' + self.source + LineEnding
    + 'destination:' + self.destination + LineEnding
    + 'storage:' + self.storage + LineEnding
    + 'mask:' + self.mask + LineEnding
    + 'skip_apply_errors:' + boolean_as_string( self.skip_apply_errors )
    + 'custom_file_processor:' + assigned_as_string( self.custom_file_processor )
    + 'progress_callback:' + assigned_as_string( self.progress_callback )
    + 'log_processor:' + assigned_as_string( self.log_processor )
end;

function tFileRecord.NeedUpdate: boolean;
begin
    result := ( ( not self.remote_hash.IsEmpty )and( self.local_hash <> self.remote_hash ) )
              or ( ( not self.storage_hash.IsEmpty )and( self.local_hash <> self.storage_hash ) );
end;

function tFileRecord.Added: boolean;
begin
    result := ( not self.remote_hash.IsEmpty )and( self.local_hash.IsEmpty );
end;

function tFileRecord.Removed: boolean;
begin
    result := ( not self.local_hash.IsEmpty )and( self.remote_hash.IsEmpty );
end;

function tFileRecord.Stored: boolean;
begin
    result := (not self.remote_hash.IsEmpty)and( not self.storage_hash.IsEmpty )and( self.remote_hash = self.storage_hash )
end;

constructor tBaseUpdater.Create( const updater_options: tUpdaterOptions );
begin
    _options := updater_options;
    options.Prepare;
    _map := tFileList.Create;
    _map.sorted := true;
    _map.Duplicates := dupIgnore;
    _aborted := false;
    _id := inttostr(random(high(longint)));
    __log__( 'options' + options.Summary );
end;

destructor tBaseUpdater.Destroy;
begin
    _map.Free;
end;

procedure tBaseUpdater.Abort;
begin
    _aborted := true;
end;

function tBaseUpdater.ApplyFile( const path: string; const source, destination: tStream ): boolean;
var
    n: int64;
begin
    try
        __log__( path + ': applying' );
        result := false;
        if assigned( options.custom_file_processor ) then
            begin
                __log__( path + ': running custom file processing' );
                __report__( path, usUPDATING, -1 );
                result := options.custom_file_processor( path, source );
            end;
        if not result then
            begin
                repeat
                    try
                        __CHECK_ABORTED_ _SET_RESULT_ false _AND_BREAK__
                        n := destination.CopyFrom( source, min( FILE_OPERATION_CHUNK_SIZE, source.size-source.position ) );
                        __report__( path, usUPDATING, __percent__( source.position, source.size ) );
                    except on exc: Exception do
                        begin
                            __log__( path + ': applying raised exception ''' + exc.tostring + '''', lmtERROR );
                            result := false;
                            raise;
                        end;
                    end;
                until n < FILE_OPERATION_CHUNK_SIZE;
                result := true;
                __log__( path + ': applyed' );
            end;
    finally
        __report__( options.destination, tUpdateStatus.usIDLE, -1 );
    end;
end;

function tBaseUpdater.CleanUp( all: boolean ): boolean;

    function clean_up( const path, mask: string ): boolean;    
    var
        list: specialize tScopeContainer<tStringList>;
        fname: string;
        n: word;
        b: boolean;
    begin
        result := true;
        try
            __report__( path, tUpdateStatus.usCLEANUP, -1 );
            list.assign( FindAllFiles( path, mask, true ) );
            __log__( path + ': found ' + inttostr( list.get.count ) + ' files' );
            n := 0;
            for fname in list.get do
                begin
                    __CHECK_ABORTED_ _SET_RESULT_ false _AND_BREAK__
                    __log__( fname + ': deleting' );
                    b := DeleteFile( fname );
                    if not b then
                        __log__( fname + ': couldn''t delete file with error ''' + SysErrorMessage(GetLastOSError) + '''', lmtWARNING );
                    result := b and result;
                    n += 1;
                    __report__( fname, tUpdateStatus.usCLEANUP, __percent__( n, list.get.count ) );
                end;
        finally
            __report__( path, tUpdateStatus.usIDLE, -1 );
        end;
    end;

begin
    __log__( options.destination + ': starting cleanup' );
    result := clean_up( options.destination, '*'+OLD_FILE_EXT );
    if all then
        result := clean_up( options.storage, '*' ) and result;
end;

function tBaseUpdater.CheckUpdates: tCheckResult;
var
 n: word;
begin
    // if map is empty then try to fill it and if filling fails of the map is empty again then something is wrong
    // hope the order is like that)
    if( _map.count = 0 )and(( not FillMap )or( _map.count = 0 ))then
        exit( crERROR );
    for n := 0 to _map.count.size - 1 do
        if _map.data[n].NeedUpdate then
            exit( crOUTDATED );
    result := crUPTODATE;
end;

function tBaseUpdater.FetchUpdates: tFetchResult;
var
    n: word;
    strm: specialize tScopeContainer<tFileStream>;
begin
    try 
        __log__( options.destination + ': fetching updates' );
        if( _map.count = 0 )and(( not FillMap )or( _map.count = 0 ))then
            exit( frERROR );
        result := frOK;
        try
            for n := 0 to _map.count - 1 do
                begin
                    __CHECK_ABORTED_ _SET_RESULT_ frABORTED _AND_BREAK__
                    if _map.data[n].NeedUpdate then
                        begin
                            if _map.data[n].Stored then
                                __LOG_MESSAGE_ _map.keys[n] + ': found at storage, skipping' _AND_CONTINUE__
                            if _map.data[n].Removed then
                                __LOG_MESSAGE_ _map.keys[n] + ': marked for removal, skipping' _AND_CONTINUE__
                            __log__( _map.keys[n] + ': opening storage stream at ' + options.storage + _map.keys[n] );
                            ForceDirectories( extractfilepath( options.storage + _map.keys[n] ) );
                            strm.assign( tFileStream.Create( options.storage + _map.keys[n], fmCreate ) );
                            __log__( _map.keys[n] + ': fetching file' );
                            if not FetchFile( _map.keys[n], strm.get ) then
                                begin
                                    result := frERROR;
                                    __log__( _map.keys[n] + ': fetching failed', lmtWARNING );
                                end;
                        end;
                    __report__( _map.keys[n], usFETCHING, __percent__( n, _map.count ) );
                end;
        except on exc: Exception do
            begin
                __log__( ': fetching raised exception ''' + exc.tostring + '''', lmtERROR );
                result := frERROR;
                raise;
            end;
        end;
    finally
        __report__( options.destination, tUpdateStatus.usIDLE, -1 );
    end;
end;

function tBaseUpdater.ApplyUpdates: tApplyResult;
var
    n: word;
    fname: string;
    source, destination: specialize tScopeContainer<tFileStream>;
begin
    try
        if( _map.count = 0 )and(( not FillMap )or( _map.count = 0 ))then
            exit( arERROR );
        if not CleanUp( false ) then
            exit( arERROR ); 
        result := arOK;
        if not options.distribution.IsEmpty then
            begin
                __log__( options.distribution + ': processing distribution' );
                try
                    __log__( options.distribution + ': opening distribution' );
                    source.assign( tFileStream.Create( options.storage + options.distribution, fmOpenRead ) );
                    if not options.custom_file_processor( options.distribution, source.get ) then
                        raise Exception.Create( 'Custom file processing returned false' );
                    source.reset;
                    FetchStorageFilesInfo;
                except on exc: Exception do
                    begin
                        __log__( 'distribution processing failed: ' + exc.tostring );
                        exit( arERROR );
                    end;  
                end;              
            end;
        for n := 0 to _map.count - 1 do
            begin
                __CHECK_ABORTED_ _SET_RESULT_ arABORTED _AND_BREAK__
                fname := _map.keys[n];
                __report__( fname, tUpdateStatus.usUPDATING, __percent__( n, _map.count ) );
                if fname = options.distribution then
                    __LOG_MESSAGE_ _map.keys[n] + ': distribution file, skipped' _AND_CONTINUE__
                if not _map.data[n].NeedUpdate then
                    __LOG_MESSAGE_ _map.keys[n] + ': up to date, skipped' _AND_CONTINUE__
                if not _map.data[n].Added then
                    begin
                        __log__( fname + ': renaming' );
                        if not RenameFile( options.destination + fname, options.destination + fname + OLD_FILE_EXT ) then
                            __LOG_MESSAGE_ fname + ': couldn''t rename file with error ''' + SysErrorMessage(GetLastOSError) + '''', lmtERROR _SET_RESULT_ arERROR _AND_BREAK__
                    end;
                if not _map.data[n].Removed then
                    try
                        if( not DirectoryExists( ExtractFilePath( options.destination + fname ) ) )
                            and( not ForceDirectories( ExtractFilePath( options.destination + fname ) ) ) then
                                begin
                                    if options.skip_apply_errors then
                                        __LOG_MESSAGE_ fname + ': no file directory (' + SysErrorMessage(GetLastOSError) + ')', lmtERROR _SET_RESULT_ arPARTIAL _AND_CONTINUE__
                                    __LOG_MESSAGE_ fname + ': no file directory (' + SysErrorMessage(GetLastOSError) + ')', lmtERROR _SET_RESULT_ arERROR _AND_BREAK__
                                end;
                        __log__( fname + ': opening source' );
                        source.assign( tFileStream.Create( options.storage + fname, fmOpenRead ) );
                        if assigned( options.custom_file_processor ) then
                            destination.reset
                        else
                            begin
                                __log__( fname + ': opening destination' );
                                destination.assign( tFileStream.Create( options.destination + fname, fmCreate ) );
                            end ;
                        try
                            if not ApplyFile( fname, source.get, destination.get ) then
                                begin
                                    if options.skip_apply_errors then
                                        __LOG_MESSAGE_ fname + ': couldn''t apply file, continue', lmtERROR _SET_RESULT_ arPARTIAL _AND_CONTINUE__
                                    __LOG_MESSAGE_ fname + ': couldn''t apply file', lmtERROR _SET_RESULT_ arERROR _AND_BREAK__
                                end;
                        except
                            if options.skip_apply_errors then
                                __LOG_MESSAGE_ fname + ': couldn''t apply file, continue', lmtERROR _SET_RESULT_ arPARTIAL _AND_CONTINUE__
                            __LOG_MESSAGE_ fname + ': couldn''t apply file', lmtERROR _SET_RESULT_ arERROR _AND_BREAK__
                        end;
                    except on exc: Exception do
                        begin
                            __log__( ': applying raised exception ''' + exc.tostring + '''', lmtERROR );
                            result := arERROR;
                            raise;
                        end;
                    end;
            end;
    finally
        __report__( options.destination, tUpdateStatus.usIDLE, -1 );
    end;
end;

function tBaseUpdater.RevertUpdates: boolean;
var
    fname: string;
    n: word;
    b: boolean;
begin
    try
        __log__( options.destination + ': reverting' );
        if( _map.count = 0 )and(( not FillMap )or( _map.count = 0 ))then
            exit( false );
        result := true;
        for n := 0 to _map.count - 1 do
            begin
                __CHECK_ABORTED_ _SET_RESULT_ false _AND_BREAK__
                fname := _map.keys[n];
                __report__( fname, tUpdateStatus.usREVERTING, __percent__( n, _map.count ) );
                if not _map.data[n].NeedUpdate then
                    __LOG_MESSAGE_ _map.keys[n] + ': up to date, skipped' _AND_CONTINUE__
                __log__( fname + ': reverting' );
                if _map.data[n].Added then // file was added -> removing
                    begin
                        __log__( fname + ': deleting' );
                        b := DeleteFile( options.destination + fname );
                        if not b then 
                            __log__( fname + ': couldn''t delete file with error ''' + SysErrorMessage(GetLastOSError) + '''', lmtWARNING );
                        result := b and result;
                    end
                else if _map.data[n].Removed then // file was removed -> restoring from .old
                    begin    
                        __log__( fname + ': restoring from ' + options.destination + fname + OLD_FILE_EXT );
                        if not FileExists( options.destination + fname + OLD_FILE_EXT ) then
                            __LOG_MESSAGE_ 'file ' + options.destination + fname + OLD_FILE_EXT + ' not found', lmtWARNING _SET_RESULT_ false _AND_CONTINUE__
                        b := RenameFile( options.destination + fname + OLD_FILE_EXT, options.destination + fname );        
                        if not b then
                            __log__( fname + ': couldn''t rename file with error ''' + SysErrorMessage(GetLastOSError) + '''', lmtWARNING );
                        result := b and result;
                    end
                else // file was changed -> removing new and restoring from .old
                    begin
                        __log__( fname + ': replacing' );
                        if not FileExists( options.destination + fname + OLD_FILE_EXT ) then
                            __LOG_MESSAGE_ 'file ' + options.destination + fname + OLD_FILE_EXT + ' not found', lmtWARNING _SET_RESULT_ false _AND_CONTINUE__
                        b := DeleteFile( options.destination + fname );
                        if not b then 
                            __log__( fname + ': couldn''t delete file with error ''' + SysErrorMessage(GetLastOSError) + '''', lmtWARNING );
                        b := RenameFile( options.destination + fname + OLD_FILE_EXT, options.destination + fname ) and b;
                            __log__( fname + ': couldn''t rename file with error ''' + SysErrorMessage(GetLastOSError) + '''', lmtWARNING );
                        result := b and result;
                    end;
            end;
    finally
        __report__( options.destination, tUpdateStatus.usIDLE, -1 );
    end;
end;

function tBaseUpdater.FetchLocalFilesInfo: boolean;
var
    list: specialize tScopeContainer<tStringList>;
    fname, rel_name: string;
    pos: integer;
    strm: specialize tScopeContainer<tFileStream>;
    data: tFileRecord;
    n: word;
begin
    result := true;
    try
        __report__( options.destination, usCHECKING_LOCAL, -1 );
        __log__( options.destination + ': fetching local files list' );
        list.assign( FindAllFiles( options.destination, options.mask, true ) );
        n := 0;
        for fname in list.get do
            begin
                __CHECK_ABORTED_ _SET_RESULT_ false _AND_BREAK__
                if fname.endswith( OLD_FILE_EXT ) then
                    continue;
                rel_name := fname.substring( length( options.destination ) );
                pos := _map.Add( rel_name );
                data := _map.Data[pos];
                __log__( rel_name + ': hashing' );
                try
                    strm.assign( tFileStream.Create( options.destination + rel_name, fmOpenRead ) );
                    data.local_hash := MD5Print( MD5Stream( strm.get ) );
                    __log__( rel_name + ': MD5Stream' );
                except
                    data.local_hash := MD5Print( MD5File( options.destination + rel_name ) );
                    __log__( rel_name + ': MD5File' );
                end;
                result := result and ( not data.local_hash.IsEmpty );
                _map.Data[pos] := data;
                n += 1;
                __report__( rel_name, usCHECKING_LOCAL, __percent__( n, list.get.count ) );
            end;
    finally
        __report__( '', usIDLE, -1 );
    end;
end;

procedure tBaseUpdater.FetchStorageFilesInfo;
var
    list: specialize tScopeContainer<tStringList>;
    fname, rel_name: string;
    pos: integer;
    strm: specialize tScopeContainer<tFileStream>;
    data: tFileRecord;
    n: word;
begin
    try
        __report__( options.storage, usCHECKING_STORAGE, -1 );
        __log__( options.storage + ': fetching storage files list' );
        list.assign( FindAllFiles( options.storage, options.mask, true ) );
        n := 0;
        for fname in list.get do
            begin
                __CHECK_ABORTED_ _AND_BREAK__
                rel_name := fname.substring( length( options.storage ) );
                pos := _map.Add( rel_name );
                data := _map.Data[pos];
                __log__( rel_name + ': hashing' );
                try
                    strm.assign( tFileStream.Create( options.storage + rel_name, fmOpenRead ) );
                    data.storage_hash := MD5Print( MD5Stream( strm.get ) );
                    __log__( rel_name + ': MD5Stream' );
                except
                    data.storage_hash := MD5Print( MD5File( options.storage + rel_name ) );
                    __log__( rel_name + ': MD5File' );
                end;
                _map.Data[pos] := data;
                n += 1;
                __report__( rel_name, usCHECKING_STORAGE, __percent__( n, list.get.count ) );
            end;
    finally
        __report__( '', usIDLE, -1 );
    end;
end;

function tBaseUpdater.FillMap: boolean;
var
    n,c: integer;
begin
    // result := FetchRemoteFiles and FetchLocalFiles; may cause to skip FetchLocalFiles
    _map.clear;
    __log__( options.source + ': collecting remote files info' );
    result := FetchRemoteFilesInfo;
    __log__( options.destination + ': collecting local files info' );
    result := FetchLocalFilesInfo and result;
    c := 0;
    if _map.count > 0 then
        for n := 0 to _map.count -1 do
            if _map.data[n].NeedUpdate then
                c += 1;
    if c > 0 then 
        begin
            __log__( options.destination + ': collecting storage files info' );
            FetchStorageFilesInfo;
        end;
    __log__( options.destination + ': total files ' + inttostr( _map.count ) + ' need update ' + inttostr( c ) );

    if _map.count > 0 then
        for n := 0 to _map.count -1 do
            __log__( Format( '%s: remote: %s local: %s storage: %s need update: %d', [_map.keys[n], _map.data[n].remote_hash, _map.data[n].local_hash, _map.data[n].storage_hash, integer(_map.data[n].NeedUpdate)] ) );
end;

procedure tBaseUpdater.__report__( const path: string; const status: tUpdateStatus; const progress_current: tUpdateProgress; const progress_total: tUpdateProgress );
var
    _progress_total: tUpdateProgress;
begin
    if progress_total < 0 then
        _progress_total := progress_current;
    if assigned( options.progress_callback ) then
        options.progress_callback( path, status, progress_current, _progress_total );
end;

function tBaseUpdater.__percent__( const current, total: word ): tUpdateProgress;
begin
    result := tUpdateProgress( ( current * 100 ) div total );
end;

procedure tBaseUpdater.__log__( const message_text: string; const message_type: tLogMessageType );
var
    smt: string;
begin
    if assigned( options.log_processor ) then
        begin
            WriteStr( smt, message_type );
            options.log_processor( 
                formatdatetime( 'dd.mm.yyyy hh:nn:ss.zzz', now )+' ['+self.ClassName+']['+instance_id+']['+smt+'] '
                    + message_text + LineEnding
                , message_type
            );
        end;
end;

procedure tBaseUpdater.log_file_map;
var
    n: word;
begin
    __log__( '->files map' );
    if _map.count > 0 then
        for n:= 0 to _map.count - 1 do
            begin
                __log__( _map.keys[n] );
                __log__( 'path:' + _map.data[n].remote_path );
                __log__( 'remote:' + _map.data[n].remote_hash );
                __log__( 'local:' + _map.data[n].local_hash );
                __log__( 'storage:' + _map.data[n].storage_hash );
            end;
    __log__( 'files map->' );
end;

initialization
    randomize;

end.
