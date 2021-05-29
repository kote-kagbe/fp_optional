unit http_updater;

{$mode objfpc}{$H+}
{$macro on}
{$inline on}
{$warn 6058 off} // suppressing "Call to subroutine "blah.blah" marked as inline is not inlined"

interface

uses base_updater, network_updater, httpsend, ssl_openssl, sysutils, classes, fgl, dateutils, math;

const
    MAX_REDIRECTION_COUNT: byte = 4;
    HTTP_CALL_INTERVAL = 100; // milliseconds

type
    tAPIParams = specialize tFPGMap<string,string>;
    tResponseLogging = ( rlNone, rlErrors, rlAll );

    tHTTPUpdater = class( tNetworkUpdater )
    private
        _last_call_dt: tDateTime;
        _http: THTTPSend;
        _api_url: string;
    protected
        _api_params: tAPIParams;

        function request( url: string; method: string; log_response: tResponseLogging = rlNone; range_start: int64 = 0; range_end: int64 = 0 ): boolean;
        function api_request( api_path: string; method: string; log_response: tResponseLogging = rlNone; range_start: int64 = 0; range_end: int64 = 0 ): boolean;

        function request_delay: word; virtual;

        function FetchFile( const path: string; const destination: tStream ): boolean; override;

        property http: tHTTPSend read _http;
        property api_url: string read _api_url write _api_url;

    public
        constructor Create( const updater_options: tUpdaterOptions ); override;
        destructor Destroy; override;
    end;

implementation

{$define LOOP_MACRO}
{$include updater_macro}

constructor tHTTPUpdater.Create( const updater_options: tUpdaterOptions );
begin
    inherited Create( updater_options );
    _api_params := tAPIParams.Create;
    _api_params.sorted := true;
    _api_params.Duplicates := dupIgnore;
    _last_call_dt := 0;
    _http := THTTPSend.Create;
    _http.Protocol := '1.1';
end;

destructor tHTTPUpdater.Destroy;
begin
    _api_params.free;
    _http.Free;
    inherited;
end;

function tHttpUpdater.request( url: string; method: string; log_response: tResponseLogging; range_start, range_end: int64 ) : boolean;

    function _request( _url: string; redirection: byte ):boolean;
    begin
        if redirection > MAX_REDIRECTION_COUNT then
	        begin
	            __log__( 'too many redirections', lmtWARNING );
	            exit( false );
	        end;
        //_http.Headers.Add( 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9' );
        //_http.Headers.Add( 'accept-encoding: gzip, deflate, br' );
        result := _http.HTTPMethod( method, _url );
	    __log__( 'RESPONSE=' + IntToStr( _http.ResultCode ) + ' ' + IntToStr( _http.Document.Size ) + ' byte(s)' );
	    if( log_response = rlAll )and( assigned( options.stream_log_processor ) )then
	        options.stream_log_processor( _http.Document );
	    _http.Document.Seek( 0, soFromBeginning );
	    if result then
	        case _http.ResultCode of
	            200..299:
	                exit( true );
	            300..399:
	                begin
	                    __log__( 'redirecting...' );
	                    _http.Headers.NameValueSeparator := ':';
	                    if _http.Headers.IndexOfName( 'Location' ) > -1 then
	                        exit( _request( _http.Headers.Values['Location'], redirection + 1 ) )
	                    else if _http.Headers.IndexOfName( 'location' ) > -1 then
	                        exit( _request( _http.Headers.Values['location'], redirection + 1 ) )
	                    else
	                        begin
	                            __log__( 'got redirection code but no Location header found', lmtERROR );
	                            exit( false );
							end ;
					end ;
	            else
                    begin
                        if( log_response = rlErrors )and( assigned( options.stream_log_processor ) )then
	                        options.stream_log_processor( _http.Document );
	                    exit( false );
                    end ;
            end
		else
	        exit( false )
    end;

var
    delay: word;
begin
    while MilliSecondsBetween( now, _last_call_dt ) < request_delay do
        begin
            delay := random( request_delay );
            __log__( Format( 'http call interval %d ms not reached, sleeping for %d ms', [http_call_interval, delay] ), lmtWARNING );
            sleep( delay );
        end;
    _last_call_dt := now;
    __log__( 'REQUEST=' + url );
    _http.Clear;
    _http.ProxyHost := proxy.address;
    _http.ProxyPass := proxy.password;
    _http.ProxyPort := proxy.port;
    _http.ProxyUser := proxy.user;
    if (range_start>0)or(range_end>0) then
        begin
            if range_end >= range_start then
                _http.Headers.Insert( 0, 'Range: bytes=' + IntToStr( range_start ) + '-' + IntToStr( range_end ) )
            else
                _http.Headers.Insert( 0, 'Range: bytes=' + IntToStr( range_start ) + '-' );
        end;
    
    result := _request( url, 0 );
end;

function tHttpUpdater.api_request( api_path: string; method: string; log_response: tResponseLogging; range_start, range_end: int64 ) : boolean;
var
    params: string;
    n: integer;
begin
    params := '';
    if _api_params.count > 0 then
        begin
            params := '?';
            for n := 0 to _api_params.count - 1 do
                params += '&' + _api_params.keys[n] + '=' + _api_params.data[n];
        end;
    result := request( _api_url + api_path + params, method, log_response, range_start, range_end );
end;

function tHttpUpdater.FetchFile( const path: string; const destination: tStream ): boolean;
var
    total, offset, current, expected: int64;
begin
    total := 0;
    offset := 0;
    result := true;
    expected := _map.KeyData[path].size;
    repeat
        if request( _map.KeyData[path].remote_path, 'GET', rlErrors, offset, offset + FILE_OPERATION_CHUNK_SIZE - 1 ) then
            begin
                current := http.Document.Size;
                total += current;
                offset += FILE_OPERATION_CHUNK_SIZE;
                destination.CopyFrom( http.Document, min( FILE_OPERATION_CHUNK_SIZE, http.Document.Size ) );
                __report__( path, usFETCHING, __percent__( total, expected ) );
            end
        else
            __LOG_MESSAGE_ 'couldn''t make request', lmtERROR _SET_RESULT_ false _AND_BREAK__;
    until( not result )or( current < FILE_OPERATION_CHUNK_SIZE )or( ( expected > 0 )and( total > expected ) );
    if ( expected > 0 )and( total > expected ) then
        begin
            __log__( 'download size exceeds expected', lmtERROR );
            result := false;
        end ;
end ;

function tHTTPUpdater.request_delay: word;
begin
    result := HTTP_CALL_INTERVAL;
end ;

initialization
    randomize;

end.
