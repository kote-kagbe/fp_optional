unit yandexdisk_updater;

{$mode objfpc}{$H+}

interface

uses base_updater, http_updater, json_api_updater;

const
    YANDEX_DISK_API = 'https://cloud-api.yandex.net/v1/disk/public/resources';
    YANDEX_DISK_API_ID_KEY = 'public_key';
    YANDEX_DISK_API_OFFSET = 'offset';
    // used when YANDEX_DISK_LIST_DOWNLOAD_LINK_FIELD missing or empty
    YANDEX_DISK_API_DOWNLOAD_PATH = '/download';

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
    
    end;

implementation

end.