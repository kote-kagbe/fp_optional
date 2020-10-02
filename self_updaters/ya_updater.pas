(*
* Efimov V.P.
* kote.kagbe@gmail.com
* 2020
*)

unit ya_updater;

{$mode objfpc}{$H+}

interface

uses
    Classes, SysUtils, http_updater, base_updater, fpjson;

const
    LIST_ADDRESS = 'https://cloud-api.yandex.net/v1/disk/public/resources?public_key=';
    DOWNLOAD_ADDRESS = 'https://cloud-api.yandex.net/v1/disk/public/resources/download?public_key=';

type
    { tYaUpdater }

    tYaUpdater = class( tHttpUpdater )
    private
        function parse_json: TJSONObject;
    protected
        function FetchFile( rel_name: string ): boolean; override;
        function CheckUpdates: boolean; OVERRIDE;
	end ;

implementation
uses LCLProc;
{ tYaUpdater }

function tYaUpdater.parse_json: TJSONObject;
var
    json: TJSONData;
begin
    log( '->parsing json...' );
    try
        json := GetJSON( http.Document );
	except on e: Exception do
        begin
            log( 'JSON PARSE ERROR=' + e.Message );
            exit( nil );
		end ;
	end ;
    if( json <> nil )and( not( json is TJSONObject ) ) then
        begin
            log( 'json data is not Object' );
            FreeThenNil( json );
            exit( nil );
		end ;
    result := json as TJSONObject;

end ;

function tYaUpdater.FetchFile( rel_name: string) : boolean;
begin

end ;

function tYaUpdater.CheckUpdates: boolean;
var
    json: TJSONObject;

	    function false_exit( status: tUpdaterResult; msg: string = '' ): boolean;
		begin
		    if not msg.IsEmpty then
		        log( msg );
	        report( status );
		    if Assigned( json ) then json.Free;
		    result := false;
		end ;

begin
    if (not _get_update_size)and(_old_hash <> EMPTY_HASH)then
        begin
            if not request( LIST_ADDRESS + _source + '&path=/hash.list', 'GET', true ) then
                exit( false_exit( turNETWORKERROR, 'failed to get hashlist info' ) );
            json := parse_json;
            if json = nil then
                exit( false_exit( turNETWORKERROR, 'failed to parse response' ) );
            if json.Find( 'md5' ) <> nil then
                begin
                    result := _old_hash <> json.Strings['md5'];
                    if result then
                        begin
                            json.Free;
                            log( 'hashlist has changed' );
                            report( turHASUPDATES );
                            exit( true )
						end
					else
                        exit( false_exit( turUPTODATE, 'hashlist has NOT changed' ) )
                end;
            json.Free;
        end;
    Result := inherited CheckUpdates;
end ;

end .

