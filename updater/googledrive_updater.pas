unit googledrive_updater;

{$mode objfpc}{$H+}
{$macro on}
{$inline on}
{$warn 6058 off} // suppressing "Call to subroutine "blah.blah" marked as inline is not inlined"

interface

uses base_updater, http_updater, json_api_updater, googledrive_secret,
     fpjson, jsonparser, sysutils, classes, fgl,
     scope_container;

const
    GOOGLE_DRIVE_API = 'https://www.googleapis.com/drive/v3/files';
    GOOGLE_DRIVE_MIME_FOLDER_TYPE = 'application/vnd.google-apps.folder';
    GOOGLE_DRIVE_FOLDER_ID_FORMAT = '''%s''+in+parents'; // %s for _shared_folder_id
    GOOGLE_DRIVE_FOLDER_ID_KEY = 'q';
    GOOGLE_DRIVE_NEXT_PAGE_TOKEN = 'pageToken';

    GOOGLE_DRIVE_LIST_NAME_FIELD = 'name';
    GOOGLE_DRIVE_LIST_TYPE_FIELD = 'mimeType';
    //GOOGLE_DRIVE_LIST_LINK_FIELD = 'webContentLink';
    GOOGLE_DRIVE_LIST_MD5_FIELD = 'md5Checksum';
    GOOGLE_DRIVE_LIST_SIZE_FIELD = 'size'; //string!
    GOOGLE_DRIVE_LIST_LIST_FIELD = 'files';
    GOOGLE_DRIVE_LIST_ID_FIELD = 'id';
    GOOGLE_DRIVE_LIST_NEXT_PAGE_TOKEN_FIELD = 'nextPageToken';

    GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE: array[0..2] of string = ( GOOGLE_DRIVE_LIST_NAME_FIELD, GOOGLE_DRIVE_LIST_TYPE_FIELD, GOOGLE_DRIVE_LIST_ID_FIELD );
    GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE_TYPES: array[0..high(GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE)] of TJSONtype = ( jtString, jtString, jtString );
    GOOGLE_DRIVE_LIST_FILE_STRUCTURE: array[0..4] of string = ( GOOGLE_DRIVE_LIST_NAME_FIELD, GOOGLE_DRIVE_LIST_TYPE_FIELD, {GOOGLE_DRIVE_LIST_LINK_FIELD,} GOOGLE_DRIVE_LIST_MD5_FIELD, GOOGLE_DRIVE_LIST_SIZE_FIELD, GOOGLE_DRIVE_LIST_ID_FIELD );
    GOOGLE_DRIVE_LIST_FILE_STRUCTURE_TYPES: array[0..high(GOOGLE_DRIVE_LIST_FILE_STRUCTURE)] of TJSONtype = ( jtString, jtString, {jtString,} jtString, jtString, jtString );

type
    { tGoogleDriveUpdater }

    tGoogleDriveUpdater = class( tJSONAPIUpdater )
    protected
        function is_folder( const j: tJSONData ): boolean;
        function is_file( const j: tJSONData ): boolean;

        function fetch_request ( const path: string; const range_start, range_end: int64 ) : boolean; override;

        // this method better be overridden with any kind of file list parsing instead of full tree walking
        function FetchRemoteFilesInfo: boolean; override;
        function FetchFile( const path: string; const destination: tStream ): boolean; override;
    public
        constructor Create( const updater_options: tUpdaterOptions ); override; 
    end;

implementation

{$define LOOP_MACRO}
{$include updater_macro}

constructor tGoogleDriveUpdater.Create( const updater_options: tUpdaterOptions );
begin
    inherited Create( updater_options );
    api_url := GOOGLE_DRIVE_API;
    _http_params.data_chunk_size := 0; // trying to avoid google restricts for calls with downloading the full file
    _http_params.request_interval := 1000;
    //_api_params.Add( 'pageSize', '2' );
end;

function tGoogleDriveUpdater.is_folder( const j: tJSONData ): boolean;
begin
    result := valid_json_object( j, GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE, GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE_TYPES );
end;

function tGoogleDriveUpdater.is_file( const j: tJSONData ): boolean;
begin
    result := valid_json_object( j, GOOGLE_DRIVE_LIST_FILE_STRUCTURE, GOOGLE_DRIVE_LIST_FILE_STRUCTURE_TYPES );
end;

function tGoogleDriveUpdater.fetch_request ( const path: string; const range_start, range_end: int64 ) : boolean;
begin
    //'https://www.googleapis.com/drive/v3/files/' + obj.Strings[GOOGLE_DRIVE_LIST_ID_FIELD] + '?alt=media&supportsAllDrives=true&key=' + googledrive_secret.KEY;
    http.Clear;
    result := api_request( _map.KeyData[path].remote_path, 'GET', rlErrors{, range_start, range_end} );
end ;

function tGoogleDriveUpdater.FetchFile( const path: string; const destination: tStream ): boolean;
begin
    _api_params.Clear;
    _api_params.Add( 'alt', 'media' );
    _api_params.Add( 'supportsAllDrives', 'true' );
    _api_params.add( 'key', googledrive_secret.KEY );
    result := inherited;
end ;

function tGoogleDriveUpdater.FetchRemoteFilesInfo: boolean;
(*
{
 "kind": "drive#fileList",
 "files": [
  {
   "kind": "drive#file",
   "name": "inner_test",
   "mimeType": "application/vnd.google-apps.folder"
  },
  {
   "kind": "drive#file",
   "name": "ACdiag-1.jpg",
   "mimeType": "image/jpeg",
   "webContentLink": "https://drive.google.com/uc?id=13PyqeBUPpQRKuJFXohWWTbYFjm5eUwEc&export=download",
   "md5Checksum": "6bb938b9ff4ec7105b4887d65aed0721",
   "size": "2796470"
  }
}
*)

    function tree_walker( const id, path: string ): boolean;
    var
        json: specialize tScopeContainer<TJSONData>;
        pair: tJsonEnum;
        data: tFileRecord;
        n: word;
        obj: tJSONObject;
        next_page_token: string;
        folders: specialize tScopeContainer<specialize tFPGMap<string,string>>;
    begin
        result := true;
        obj := nil;
        _api_params.AddOrSetData( GOOGLE_DRIVE_FOLDER_ID_KEY, Format( GOOGLE_DRIVE_FOLDER_ID_FORMAT, [id] ) );
        next_page_token := '';
        folders.assign( specialize tFPGMap<string,string>.Create );
        repeat
            __CHECK_ABORTED_ _SET_RESULT_ false _AND_BREAK__
            if not next_page_token.IsEmpty then
                _api_params.AddOrSetData( GOOGLE_DRIVE_NEXT_PAGE_TOKEN, next_page_token )
            else
                _api_params.Remove( GOOGLE_DRIVE_NEXT_PAGE_TOKEN );
            http.Clear;
            if api_request( '', 'GET', rlAll ) then
                begin
                    json.assign( GetJSON( http.Document ) );
                    if ( valid_json_object( json.get ) )
                       and( valid_json_array( ( json.get as tJSONObject ).Find( GOOGLE_DRIVE_LIST_LIST_FIELD ) ) )
                    then
                        begin
                            if(json.get as TJSONObject).Find( GOOGLE_DRIVE_LIST_NEXT_PAGE_TOKEN_FIELD ) <> nil then
                                next_page_token := (json.get as TJSONObject).Strings[GOOGLE_DRIVE_LIST_NEXT_PAGE_TOKEN_FIELD]
                            else
                                next_page_token := '';
                            for pair in ( ( json.get as tJSONObject )[GOOGLE_DRIVE_LIST_LIST_FIELD] as tJsonArray ) do
                                begin
                                    if is_file( pair.value ) then
                                        begin
                                            obj := pair.value as tJSONObject;
                                            n := _map.add( path + obj.Strings[GOOGLE_DRIVE_LIST_NAME_FIELD] );
                                            data := _map.data[n];
                                            data.remote_hash := obj.Strings[GOOGLE_DRIVE_LIST_MD5_FIELD];
                                            data.remote_path := '/' + obj.Strings[GOOGLE_DRIVE_LIST_ID_FIELD];
                                            data.size := StrToInt64Def( obj.Strings[GOOGLE_DRIVE_LIST_SIZE_FIELD], 0 );
                                            _map.data[n] := data;
                                        end
                                    else if is_folder( pair.value ) then
                                        begin
                                            obj := pair.value as tJSONObject;
                                            //result := tree_walker( obj.Strings[GOOGLE_DRIVE_LIST_ID_FIELD], path + obj.Strings[GOOGLE_DRIVE_LIST_NAME_FIELD] + DirectorySeparator );
                                            folders.get.Add( obj.Strings[GOOGLE_DRIVE_LIST_ID_FIELD], obj.Strings[GOOGLE_DRIVE_LIST_NAME_FIELD] );
                                        end
                                    else
                                        __LOG_MESSAGE_ GOOGLE_DRIVE_LIST_LIST_FIELD + '[' + inttostr(pair.keynum) + '] is not a valid object', lmtWARNING _AND_CONTINUE__

                                end
                        end
                    else
                        __LOG_MESSAGE_ 'failed to extract response data', lmtERROR _SET_RESULT_ false _AND_BREAK__
                end
            else
                __LOG_MESSAGE_ 'failed to make a request', lmtERROR _SET_RESULT_ false _AND_BREAK__
        until( not valid_json_object( json.get ) )or( ( json.get as TJSONObject ).Find( GOOGLE_DRIVE_LIST_NEXT_PAGE_TOKEN_FIELD ) = nil );

        n := 0;
        while( result )and( n < folders.get.Count )do
            begin
                __CHECK_ABORTED_ _SET_RESULT_ false _AND_BREAK__
                __log__( 'processing folder ' + path + folders.get.DATA[n] + DirectorySeparator );
                result := tree_walker( folders.get.keys[n], path + folders.get.DATA[n] + DirectorySeparator );
                n += 1;
            end ;
    end;

begin
    _api_params.Clear;
    _api_params.add( 'key', googledrive_secret.KEY );
    _api_params.add( 'fields', 'files(kind,name,md5Checksum,size,mimeType,id),kind,nextPageToken' );
    result := tree_walker( options.source, '' );
end;

end.
