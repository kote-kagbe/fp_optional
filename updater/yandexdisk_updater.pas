unit yandexdisk_updater;

{$mode objfpc}{$H+}
{$macro on}
{$inline on}
{$warn 6058 off} // suppressing "Call to subroutine "blah.blah" marked as inline is not inlined"

interface

uses base_updater, http_updater, json_api_updater, classes, sysutils;

const
    YANDEX_DISK_API = 'https://cloud-api.yandex.net/v1/disk/public/resources';
    YANDEX_DISK_API_ID_KEY = 'public_key';
    YANDEX_DISK_API_OFFSET = 'offset';
    // used when YANDEX_DISK_LIST_DOWNLOAD_LINK_FIELD missing or empty
    YANDEX_DISK_API_DOWNLOAD = '/download';
    YANDEX_DISK_API_DOWNLOAD_PATH = 'path';

    // list fields
    YANDEX_DISK_LIST_PUBLIC_KEY_FIELD = 'public_key'; // /
    YANDEX_DISK_LIST_LIST_FIELD = '_embedded'; // /
    YANDEX_DISK_LIST_ITEMS_FIELD = 'items'; // /_embedded/
    YANDEX_DISK_LIST_NAME_FIELD = 'name'; // /_embedded/items[*]/
    YANDEX_DISK_LIST_MD5_FIELD = 'md5'; // /_embedded/items[*]/
    YANDEX_DISK_LIST_TYPE_FIELD = 'type'; // /_embedded/items[*]/
    YANDEX_DISK_LIST_SIZE_FIELD = 'size'; // /_embedded/items[*]/
    YANDEX_DISK_LIST_LIMIT_FIELD = 'limit'; // /_embedded
    YANDEX_DISK_LIST_OFFSET_FIELD = 'offset'; // /_embedded
    YANDEX_DISK_LIST_TOTAL_ITEMS_COUNT_FIELD = 'total'; // /_embedded
    YANDEX_DISK_LIST_DOWNLOAD_LINK_FIELD = 'file'; // /_embedded/items[*]/

    YANDEX_DISK_LIST_FOLDER_TYPE = 'dir';
    YANDEX_DISK_LIST_FILE_TYPE = 'file';

    // download api result format
    // used when YANDEX_DISK_LIST_DOWNLOAD_LINK_FIELD missing or empty
    YANDEX_DISK_DOWNLOAD_LINK_FIELD = 'href';
    YANDEX_DISK_DOWNLOAD_METHOD_FIELD = 'method';
    YANDEX_DISK_DOWNLOAD_TEMPLATED_FIELD = 'templated'; // what when true?

type
    tYandexDiskUpdater = class( tJSONAPIUpdater )
    protected
        function fetch_request( const path: string; const range_start, range_end: int64 ): boolean; override;

        // this method better be overridden with any kind of file list parsing instead of full tree walking
        function FetchRemoteFilesInfo: boolean; override;
        //function FetchFile( const path: string; const destination: tStream ): boolean; override;
    public
        constructor Create( const updater_options: tUpdaterOptions ); override; 
    end;

implementation

{$define LOOP_MACRO}
{$include updater_macro}

constructor tYandexDiskUpdater.Create( const updater_options: tUpdaterOptions );
begin
    inherited Create( updater_options );
    api_url := YANDEX_DISK_API;
    _http_params.data_chunk_size := 0;
    _http_params.request_interval := 1000;
end;

function tYandexDiskUpdater.fetch_request( const path: string; const range_start, range_end: int64 ): boolean;
var
    method: string;
begin
    method := 'GET';
    if _map.KeyData[path].remote_path.IsEmpty then
        begin
            _api_params.Clear;
            _api_params.Add( YANDEX_DISK_API_ID_KEY, options.source );
            _api_params.Add( YANDEX_DISK_API_DOWNLOAD_PATH, '/' + path );
            if api_request( YANDEX_DISK_API_DOWNLOAD, 'GET', rlErrors ) then
                begin
                    // resolve the download link via api

                    // _map.KeyData[path].remote_path := 
                    // method := 
                end
            else
                __LOG_MESSAGE_ path + ': couldn''t resolve download link', lmtERROR _SET_RESULT_ false _AND_EXIT__
        end;
    result := request( _map.KeyData[path].remote_path, method, rlErrors, range_start, range_end );
end;

function tYandexDiskUpdater.FetchRemoteFilesInfo: boolean;
begin

end;

end.