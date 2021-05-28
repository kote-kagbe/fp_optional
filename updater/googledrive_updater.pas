unit googledrive_updater;

{$mode objfpc}{$H+}
{$macro on}
{$inline on}
{$warn 6058 off} // suppressing "Call to subroutine "blah.blah" marked as inline is not inlined"

interface

uses base_updater, http_updater, googledrive_secret, fpjson, sysutils, classes, scope_container, jsonparser;

const
    GOOGLE_DRIVE_API = 'https://www.googleapis.com/drive/v3/files';
    GOOGLE_DRIVE_MIME_FOLDER_TYPE = 'application/vnd.google-apps.folder';
    GOOGLE_DRIVE_FOLDER_ID_FORMAT = '''%s''+in+parents'; // %s for _shared_folder_id
    GOOGLE_DRIVE_FOLDER_ID_KEY = 'q';

    GOOGLE_DRIVE_LIST_NAME_FIELD = 'name';
    GOOGLE_DRIVE_LIST_TYPE_FIELD = 'mimeType';
    GOOGLE_DRIVE_LIST_LINK_FIELD = 'webContentLink';
    GOOGLE_DRIVE_LIST_MD5_FIELD = 'md5Checksum';
    GOOGLE_DRIVE_LIST_SIZE_FIELD = 'size'; //string!
    GOOGLE_DRIVE_LIST_LIST_FIELD = 'files';
    GOOGLE_DRIVE_LIST_ID_FIELD = 'id';

    GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE: array[0..2] of string = ( GOOGLE_DRIVE_LIST_NAME_FIELD, GOOGLE_DRIVE_LIST_TYPE_FIELD, GOOGLE_DRIVE_LIST_ID_FIELD );
    GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE_TYPES: array[0..high(GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE)] of TJSONtype = ( jtString, jtString, jtString );
    GOOGLE_DRIVE_LIST_FILE_STRUCTURE: array[0..5] of string = ( GOOGLE_DRIVE_LIST_NAME_FIELD, GOOGLE_DRIVE_LIST_TYPE_FIELD, GOOGLE_DRIVE_LIST_LINK_FIELD, GOOGLE_DRIVE_LIST_MD5_FIELD, GOOGLE_DRIVE_LIST_SIZE_FIELD, GOOGLE_DRIVE_LIST_ID_FIELD );
    GOOGLE_DRIVE_LIST_FILE_STRUCTURE_TYPES: array[0..high(GOOGLE_DRIVE_LIST_FILE_STRUCTURE)] of TJSONtype = ( jtString, jtString, jtString, jtString, jtString, jtString );

type
    tArrayOfString = array of string;
    tJSONTypesArray = array of tJSONType;

    tGoogleDriveUpdater = class( tHTTPUpdater )
    protected

        generic function valid_json <T:tJSONData> ( const j: tJSONData ): boolean;
        generic function valid_json_object( const j: tJSONData; const fields: tArrayOfString = nil; field_types: tJSONTypesArray = nil ): boolean;
        function valid_json_array( const j: tJSONData ): boolean;
        function is_folder( const j: tJSONData ): boolean;
        function is_file( const j: tJSONData ): boolean;

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
    _api_params.add( 'key', googledrive_secret.KEY );
    _api_params.add( 'fields', 'files(kind,name,md5Checksum,size,mimeType,webContentLink,id),kind,nextPageToken' );
end;

generic function tGoogleDriveUpdater.valid_json<T>( const j: tJSONData ): boolean;
begin
    result := ( j <> nil ) and ( j is T ) and ( not( j.IsNull ) );
end;

function tGoogleDriveUpdater.valid_json_object( const j: tJSONData; const fields: tArrayOfString; field_types: tJSONTypesArray ): boolean;
var
    n: integer;
begin
    if( ( fields <> nil ) xor ( field_types <> nil ) )or( length( fields ) <> length( field_types ) ) then
        raise Exception.Create( 'Fields and types must be defined either both or none' );
    result := specialize valid_json<tJSONObject>( j );
    if( result )and( length( fields ) > 0 )then
        for n := 0 to high( fields ) do
            if( ( j as tJSONObject ).Find( fields[n] ) = nil )or( ( j as tJSONObject ).Find( fields[n] ).JSONType <> field_types[n] ) then
                exit( false );
end;

function tGoogleDriveUpdater.valid_json_array( const j: tJSONData ): boolean;
begin
    result := specialize valid_json<tJSONArray>( j );
end;

function tGoogleDriveUpdater.is_folder( const j: tJSONData ): boolean;
begin
    result := valid_json_object( j, GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE, GOOGLE_DRIVE_LIST_FOLDER_STRUCTURE_TYPES );
end;

function tGoogleDriveUpdater.is_file( const j: tJSONData ): boolean;
begin
    result := valid_json_object( j, GOOGLE_DRIVE_LIST_FILE_STRUCTURE, GOOGLE_DRIVE_LIST_FILE_STRUCTURE_TYPES );
end;

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
    begin
        result := true;
        _api_params.AddOrSetData( GOOGLE_DRIVE_FOLDER_ID_KEY, Format( GOOGLE_DRIVE_FOLDER_ID_FORMAT, [id] ) );
        if api_request( GOOGLE_DRIVE_API, 'GET', true ) then
            begin
                json.assign( GetJSON( _http.Document ) );
                if ( valid_json_object( json.get ) )
                   and( valid_json_array( ( json.get as tJSONObject ).Find( GOOGLE_DRIVE_LIST_LIST_FIELD ) ) )
                then
                    for pair in ( ( json.get as tJSONObject )[GOOGLE_DRIVE_LIST_LIST_FIELD] as tJsonArray ) do
                        begin
                            if is_file( pair.value ) then
                                begin
                                    obj := pair.value as tJSONObject;
                                    n := _map.add( path + obj.Strings[GOOGLE_DRIVE_LIST_NAME_FIELD] );
                                    data := _map.data[n];
                                    data.remote_hash := obj.Strings[GOOGLE_DRIVE_LIST_MD5_FIELD];
                                    data.remote_path := obj.Strings[GOOGLE_DRIVE_LIST_LINK_FIELD];
                                    data.size := StrToInt64Def( obj.Strings[GOOGLE_DRIVE_LIST_SIZE_FIELD], 0 );
                                    _map.data[n] := data;
                                end
                            else if is_folder( pair.value ) then
                                begin
                                    obj := pair.value as tJSONObject;
                                    result := tree_walker( obj.Strings[GOOGLE_DRIVE_LIST_ID_FIELD], path + obj.Strings[GOOGLE_DRIVE_LIST_NAME_FIELD] + DirectorySeparator );
                                end
                            else
                                __LOG_MESSAGE_ GOOGLE_DRIVE_LIST_LIST_FIELD + '[' + inttostr(pair.keynum) + '] is not object', lmtWARNING _AND_CONTINUE__
                            
                        end
                else
                    begin
                        __log__( 'failed to extract response data', lmtERROR );
                        result := false;
                    end;
            end
        else
            begin
                __log__( 'failed to make a request', lmtERROR );
                result := false;
            end;
    end;

begin
    result := tree_walker( options.source, '' );
    writeln('QQQQ ', result)
end;

function tGoogleDriveUpdater.FetchFile( const path: string; const destination: tStream ): boolean;
begin

end;

end.