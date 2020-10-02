(*
* Efimov V.P.
* kote.kagbe@gmail.com
* 2020
*)

unit http_updater;

{$mode objfpc}{$H+}

interface

uses
    Classes, SysUtils, base_updater, httpsend, ssl_openssl, math;

type

	{ tHttpUpdater }

    tHttpUpdater = class( tBaseUpdater )
        protected
            http: THTTPSend;

            function request( url: string; method: string; log_data: boolean = true; range_start: int64 = 0; range_end: int64 = 0 ): boolean;
	end ;

implementation

{ tHttpUpdater }

function tHttpUpdater.request( url: string; method: string; log_data: boolean; range_start, range_end: int64 ) : boolean;

    function _request( _url: string; redirection: byte ):boolean;
    begin
        if redirection > 4 then
	        begin
	            log( 'too many redirections' );
	            exit( false );
	        end;
        result := http.HTTPMethod( method, _url );
	    log( 'RESPONSE=' + IntToStr( http.ResultCode ) + ' ' + IntToStr( http.Document.Size ) + ' byte(s)' );
	    if log_data then
	        begin
			    log( '============================================' );
	            if Assigned( _log ) then
	    		    _log.CopyFrom( http.Document, min( 10*1024, http.Document.Size ) );
			    log( '' );
			    log( '============================================' );
	        end;
	    http.Document.Seek( 0, soFromBeginning );
	    if result then
	        case http.ResultCode of
	            200:
	                exit( true );
	            300..399:
	                begin
	                    log( 'redirecting...' );
	                    http.Headers.NameValueSeparator := ':';
	                    if http.Headers.IndexOfName( 'Location' ) > -1 then
	                        exit( _request( http.Headers.Values['Location'], redirection + 1 ) )
	                    else if http.Headers.IndexOfName( 'location' ) > -1 then
	                        exit( _request( http.Headers.Values['location'], redirection + 1 ) )
	                    else
	                        begin
	                            log( 'got redirection code but no Location header found' );
	                            exit( false );
							end ;
					end ;
	            else
	                exit( false );
			end
		else
	        exit( false )
    end;

begin
    log( 'REQUEST=' + url );
    http.Clear;
    http.ProxyHost := proxy.server;
    http.ProxyPass := proxy.password;
    http.ProxyPort := proxy.port;
    http.ProxyUser := proxy.user;
    if (range_start>0)or(range_end>0) then
        begin
            if range_end >= range_start then
                http.Headers.Insert( 0, 'bytes=' + IntToStr( range_start ) + '-' + IntToStr( range_end ) )
            else
                http.Headers.Insert( 0, 'bytes=' + IntToStr( range_start ) + '-' );
        end;
    result := _request( url, 0 );
end ;

end .

