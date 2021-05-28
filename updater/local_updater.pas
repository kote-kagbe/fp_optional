unit local_updater;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$macro on}
{$inline on}
{$warn 6058 off} // suppressing "Call to subroutine "blah.blah" marked as inline is not inlined"

interface

uses base_updater, classes, scope_container, fileutil, md5, md5_stream, sysutils, math;

type
    tLocalUpdater = class( tBaseUpdater )
    protected
        function FetchRemoteFilesInfo: boolean; override;
        function FetchFile( const path: string; const destination: tStream ): boolean; override;
    
    end;

implementation

{$define LOOP_MACRO}
{$include updater_macro}

function tLocalUpdater.FetchRemoteFilesInfo: boolean;
var
    list: specialize tScopeContainer<tStringList>;
    strm: specialize tScopeContainer<tFileStream>;
    data: tFileRecord;
    n: word;
    fname, source,rel_name: string;
    pos: integer;
begin
    result := true;
    try
        source := options.source;
        if not source.EndsWith( DirectorySeparator ) then
            source += DirectorySeparator;
        __report__( source, usCHECKING_REMOTE, -1 );
        __log__( source + ': fetching remote files list' );
        if not DirectoryExists( source ) then
            raise Exception.Create( source + ' path does not exist' );
        list.assign( FindAllFiles( source, options.mask, true ) );
        n := 0;
        for fname in list.get do
            begin
                __CHECK_ABORTED_ _SET_RESULT_ false _AND_BREAK__
                rel_name := fname.substring( length( source ) );
                pos := _map.Add( rel_name );
                data := _map.Data[pos];
                __log__( rel_name + ': hashing' );
                try
                    strm.assign( tFileStream.Create( source + rel_name, fmOpenRead ) );
                    data.size := strm.get.size;
                    data.remote_hash := MD5Print( MD5Stream( strm.get ) );
                    __log__( rel_name + ': MD5Stream' );
                except
                    data.remote_hash := MD5Print( MD5File( source + rel_name ) );
                    __log__( rel_name + ': MD5File' );
                end;
                result := result and ( not data.remote_hash.IsEmpty );
                _map.Data[pos] := data;
                n += 1;
                __report__( rel_name, usCHECKING_REMOTE, __percent__( n, list.get.count ) );
            end;
    finally
        __report__( '', usIDLE, -1 );
    end;
end;

function tLocalUpdater.FetchFile( const path: string; const destination: tStream ): boolean;
var
    n: int64;
    source: specialize tScopeContainer<tFileStream>;
    src: string;
begin
    try
        src := options.source;
        if not src.EndsWith( DirectorySeparator ) then
            src += DirectorySeparator;
        __report__( options.source, tUpdateStatus.usFETCHING, -1 );
        result := true;
        __log__( src + path + ': fetching' );
        __log__( src + path + ': opening source' );
        try
            source.assign( tFileStream.Create( src + path, fmOpenRead ) );
        except on exc: Exception do
            begin
                __log__( path + ': opening source raised exception ''' + exc.tostring + '''', lmtERROR );
                result := false;
                exit;
            end;
        end;
        __log__( src + path + ': recieving' );
        repeat
            try
                __CHECK_ABORTED_ _SET_RESULT_ false _AND_BREAK__
                n := destination.CopyFrom( source.get, min( FILE_OPERATION_CHUNK_SIZE, source.get.size-source.get.position ) );
                __report__( path, usFETCHING, __percent__( source.get.position, source.get.size ) );
            except on exc: Exception do
                begin
                    __log__( src + path + ': fetching raised exception ''' + exc.tostring + '''', lmtERROR );
                    result := false;
                    break;
                end;
            end;
        until n < FILE_OPERATION_CHUNK_SIZE;
        __log__( src + path + ': fetched' );
    finally
        __report__( options.destination, tUpdateStatus.usIDLE, -1 );
    end;
end;

end.