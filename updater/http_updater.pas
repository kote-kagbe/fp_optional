unit http_updater;

{$mode objfpc}{$H+}

interface

uses base_updater, network_updater, httpsend, ssl_openssl, sysutils, classes, fgl, dateutils;

const
    MAX_REDIRECTION_COUNT: byte = 4;
    HTTP_CALL_INTERVAL = 100; // milliseconds

type
    tAPIParams = specialize tFPGMap<string,string>;

    tHTTPUpdater = class( tNetworkUpdater )
    private
        _http_call_interval: int64;
        _last_call_dt: tDateTime;
        _http: THTTPSend;
        _api_url: string;
    protected
        _api_params: tAPIParams;

        function request( url: string; method: string; log_data: boolean = true; range_start: int64 = 0; range_end: int64 = 0 ): boolean;
        function api_request( api_path: string; method: string; log_data: boolean = true; range_start: int64 = 0; range_end: int64 = 0 ): boolean;

        property http: tHTTPSend read _http;
        property api_url: string read _api_url write _api_url;

    public
        constructor Create( const updater_options: tUpdaterOptions ); override;
        destructor Destroy; override;

        property http_call_interval: int64 read _http_call_interval write _http_call_interval;
    end;

implementation

constructor tHTTPUpdater.Create( const updater_options: tUpdaterOptions );
begin
    inherited Create( updater_options );
    _api_params := tAPIParams.Create;
    _api_params.sorted := true;
    _api_params.Duplicates := dupIgnore;
    _http_call_interval := HTTP_CALL_INTERVAL;
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

function tHttpUpdater.request( url: string; method: string; log_data: boolean; range_start, range_end: int64 ) : boolean;

    function _request( _url: string; redirection: byte ):boolean;
    begin
        if redirection > MAX_REDIRECTION_COUNT then
	        begin
	            __log__( 'too many redirections', lmtWARNING );
	            exit( false );
	        end;
        result := _http.HTTPMethod( method, _url );
	    __log__( 'RESPONSE=' + IntToStr( _http.ResultCode ) + ' ' + IntToStr( _http.Document.Size ) + ' byte(s)' );
	    if( log_data )and( assigned( options.stream_log_processor ) )then
	        options.stream_log_processor( _http.Document );
	    _http.Document.Seek( 0, soFromBeginning );
	    if result then
	        case _http.ResultCode of
	            200:
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
	                exit( false );
			end
		else
	        exit( false )
    end;

var
    delay: int64;
begin
    while MilliSecondsBetween( now, _last_call_dt ) < http_call_interval do
        begin
            delay := _http_call_interval div 2;
            __log__( Format( 'http call interval %d not reached, sleeping for %d', [http_call_interval, delay] ), lmtWARNING );
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
                _http.Headers.Insert( 0, 'bytes=' + IntToStr( range_start ) + '-' + IntToStr( range_end ) )
            else
                _http.Headers.Insert( 0, 'bytes=' + IntToStr( range_start ) + '-' );
        end;
    
    result := _request( url, 0 );
end;

function tHttpUpdater.api_request( api_path: string; method: string; log_data: boolean; range_start, range_end: int64 ) : boolean;
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
    result := request( _api_url + api_path + params, method, log_data, range_start, range_end );
end;

end.
