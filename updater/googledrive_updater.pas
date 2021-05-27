unit googledrive_updater;

{$mode objfpc}{$H+}
{$inline on}
{$warn 6058 off} // suppressing "Call to subroutine "blah.blah" marked as inline is not inlined"

interface

uses base_updater, http_updater, googledrive_secret, fpjson, sysutils, classes;

const
    GOOGLE_DRIVE_API = 'https://www.googleapis.com/drive/v3/files';
    GOOGLE_DRIVE_MIME_FOLDER_TYPE = 'application/vnd.google-apps.folder';
    GOOGLE_DRIVE_FOLDER_ID_FORMAT = '''%s''+in+parents'; // %s for _shared_folder_id

type
    tGoogleDriveUpdater = class( tHTTPUpdater )
    private
        procedure _SetSharedFolderId( const id: string );
    protected
        _shared_folder_id: string;

        // this method better be overridden with any kind of file list parsing instead of full tree walking
        function FetchRemoteFilesInfo: boolean; override;
        function FetchFile( const path: string; const destination: tStream ): boolean; override;
    public
        constructor Create( const updater_options: tUpdaterOptions ); override; 
    
        property shared_folder_id: string read _shared_folder_id write _SetSharedFolderId;
    end;

implementation

constructor tGoogleDriveUpdater.Create( const updater_options: tUpdaterOptions );
begin
    inherited Create( updater_options );
    _api_params.add( 'key', googledrive_secret.KEY );
    _api_params.add( 'fields', 'files(kind,name,md5Checksum,size,mimeType,webContentLink),kind,nextPageToken' );
end;

procedure tGoogleDriveUpdater._SetSharedFolderId( const id: string );
begin
    _shared_folder_id := id;
    _api_params.add( 'q', Format( GOOGLE_DRIVE_FOLDER_ID_FORMAT, [id] ) );
end;

function tGoogleDriveUpdater.FetchRemoteFilesInfo: boolean;
begin

end;

function tGoogleDriveUpdater.FetchFile( const path: string; const destination: tStream ): boolean;
begin

end;

end.