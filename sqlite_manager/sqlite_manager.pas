unit sqlite_manager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, sqldb, data_module_unit, blob_manager_unit, LResources,
  Dialogs, Forms, FileUtil, Controls, strutils, db, dateutils;

type

  { tSQLiteManager }

  tSQLiteManager = class(TComponent)
  private
    _db_file: string;
    _db_folder: string;
    _db_filename: string;
    _sql_log: boolean;
    _cnv_log: boolean;
    _sql_log_file: TFileStream;
    _blob_manager: tBlobManager;
    _use_blobs: boolean;
    _blob_table: string;
    _blob_pk: string;
    _fk_check: boolean;

    procedure OnSQLLog( Sender: TSQLConnection; EventType: TDBEventType; const Msg: String );
    function IsConnected: boolean;
    procedure MakeBackup;
    function CheckParam( const pname: string; const ptype: TFieldType ): tParam;
  protected

  public
    constructor Create( TheOwner: TComponent ); override;
    destructor Destroy; override;

    function Open: word;
    procedure Close;

    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;

    procedure SetParam( const pname: string; const pvalue: string ); overload;
    procedure SetParam( const pname: string; const pvalue: LongInt ); overload;
    procedure SetParam( const pname: string; const pvalue: Double ); overload;
    procedure SetParam( const pname: string; const pvalue: boolean ); overload;
    procedure SetParam( const pname: string; const pvalue: TDateTime ); overload;
    procedure ClearParams;

    procedure Execute( const sql: string; const with_transaction: boolean = false );
    procedure Select( const sql: string );

    procedure First;
    function Next( const rewind: boolean = false ): boolean;

    function FieldAsString( const field: string ): string;
    function FieldAsLongint( const field: string ): LongInt;
    function FieldAsBoolean( const field: string ): boolean;
    function FieldAsDouble( const field: string ): double;
    function FieldIsNull( const field: string ): boolean;
    function FieldAsDateTime( const field: string ): TDateTime;

    procedure ReadBlob( const id: word; const strm: tStream );
    function WriteBlob( const strm: tStream; const id: word = 0; use_transaction: boolean = true ): word;

    property Connected: boolean read IsConnected;

    procedure ForeignKeys( const enable: boolean );

  published
    property DatabaseFile: string read _db_file write _db_file;
    property SQLLogging: boolean read _sql_log write _sql_log default true;
    property DBConverterLogging: boolean read _cnv_log write _cnv_log default true;
    property UseBlobs: boolean read _use_blobs write _use_blobs default false;
    property BlobTable: string read _blob_table write _blob_table;
    property BlobPK: string read _blob_pk write _blob_pk;
    property ForeignKeyCheck: boolean read _fk_check write _fk_check default true;
  end;

procedure Register;

implementation
uses database_converter_unit;

procedure Register;
begin
  RegisterComponents('SQLdb', [tSQLiteManager]);
end;

{ tSQLiteManager }

procedure tSQLiteManager.OnSQLLog( Sender: TSQLConnection;
		EventType: TDBEventType; const Msg: String) ;
var
    txt: string;
begin
    txt := DateTimeToStr( now ) + ' ' + msg + #13;
    self._sql_log_file.Write( txt[1], length(txt) );
end ;

function tSQLiteManager.IsConnected: boolean;
begin
    result := data_module.sqlite.Connected;
end ;

procedure tSQLiteManager.MakeBackup;
var
    fname, bname: string;
begin
    data_module.sqlite.Close( true );
    ForceDirectories( self._db_folder + 'backup' );
    fname := StringReplace( DateTimeToStr( Now ), ':', '_', [rfReplaceAll] );
    bname := self._db_folder + 'backup' + DirectorySeparator + self._db_filename + '.' + fname;
    try
        CopyFile( self._db_file, bname, [cffOverwriteFile], true );
    except on e: Exception do
        if MessageDlg( 'Couldn''t create backup'#13 + e.Message + #13'Proceed without backup?', mtConfirmation, [mbYes, mbNo], 0 ) = mrNo then
	        halt;
	end ;
    data_module.sqlite.Open
end ;

function tSQLiteManager.CheckParam( const pname: string;
	const ptype: TFieldType): tParam ;
var
    param: TParam;
begin
    param := data_module.query.Params.FindParam( pname );
    if( param <> nil )and( param.DataType <> ptype )then
        begin
            data_module.query.Params.RemoveParam( param );
            FreeAndNil( param );
		end ;
	if param = nil then
        param := data_module.query.Params.CreateParam( ftString, pname, ptInput );
    result := param;
end ;

constructor tSQLiteManager.Create( TheOwner: TComponent) ;
begin
    inherited Create( TheOwner) ;
    SQLLogging := true;
    DBConverterLogging := true;
    DatabaseFile := 'sqlite_manager.db';
    UseBlobs := false;
    BlobTable := '';
    BlobPK := 'rowid';
    ForeignKeyCheck := true;
end ;

destructor tSQLiteManager.Destroy;
begin
    if data_module.sqlite.Connected then
        Close;
    inherited Destroy;
end ;

function tSQLiteManager.Open: word;
var
    converter: tDatabaseConverter;
begin
    if data_module.sqlite.Connected then
        raise Exception.Create( 'Database is already connected' );
    if self.DatabaseFile = '' then
        raise Exception.Create( 'Database file name is not defined' );
    if self.UseBlobs and self.BlobTable.IsEmpty then
        raise Exception.Create( 'Blobs are enabled but blob table is not defined' );
    if self.BlobTable = tBlobManager.BlobTableName then
        raise Exception.Create( 'Inappropriate blob table name' );
    if self.UseBlobs and self.BlobPK.IsEmpty then
        raise Exception.Create( 'Blobs are enabled but blob primary key is not defined' );
    if self.UseBlobs and ( self.BlobPK = 'rowid' ) then
        MessageDlg( 'Blob table PK with name ''rowid'' has some unresoved issues and may produce various errors', mtWarning, [mbOK], 0 );
    self._db_filename := ExtractFileName( self.DatabaseFile );
    self._db_folder := ExtractFilePath( self.DatabaseFile );
    if self._db_folder = '' then
        self._db_folder := ExtractFilePath( Application.ExeName );
    if not DirectoryExists( self._db_folder ) then
        raise Exception.Create( 'Database path ' + self._db_folder + ' does not exist' );
    if self._sql_log then
        begin
            try
                self._sql_log_file := tFileStream.Create( self._db_folder + self._db_filename + '.sql.log', fmCreate );
                data_module.sqlite.OnLog := @self.OnSQLLog;
            except on e: exception do
                begin
                    self._sql_log := false;
                    MessageDlg( 'Couldn''t open log file'#13 + e.Message, mtError, [mbOK], 0 );
				end ;
			end ;
		end
    else
        data_module.sqlite.OnLog := nil;
    data_module.sqlite.DatabaseName := self.DatabaseFile;
    ForeignKeys( self._fk_check );
    data_module.sqlite.Open;
    if self._fk_check then
        begin
		    Select( 'pragma foreign_key_check' );
		    if Next( true ) then
		        MessageDlg( 'Database foreign key check failed!'#13'Maintenance needed', mtWarning, [mbOK], 0 );
		end ;
	converter := tDatabaseConverter.Create( self._db_folder, self._db_filename, self._cnv_log, @self );
    if converter.NeedConvertation then
        begin
            MakeBackup;
            converter.Run;
            //if TRUE after convertation, then converters failed
            if converter.NeedConvertation then
                begin
                    MessageDlg( 'Converter(s) failed'#13'Check ' + self._db_file + '.converter.log', mtError, [mbOK], 0 );
                    result := converter.Version;
                    converter.Free;
                    Close;
                    exit;
				end ;
		end ;
	result := converter.Version;
    converter.Free;
    if self._use_blobs then
        self._blob_manager := tBlobManager.Create( self._db_folder, self._db_filename, self._blob_table, self._blob_pk, @self );
end ;

procedure tSQLiteManager.Close;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if self._sql_log then
        begin
            self._sql_log_file.Free;
            data_module.sqlite.OnLog := nil;
		end ;
    if self._use_blobs and Assigned( self._blob_manager ) then
        self._blob_manager.Free;
    data_module.sqlite.Close( true );
end ;

procedure tSQLiteManager.StartTransaction;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if data_module.transaction.Active then
        raise Exception.Create( 'Transaction is already started' );
    data_module.transaction.StartTransaction;
end ;

procedure tSQLiteManager.Commit;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.transaction.Active then
        raise Exception.Create( 'Transaction is not active' );
    data_module.transaction.Commit;
end ;

procedure tSQLiteManager.Rollback;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    {if not data_module.transaction.Active then
        raise Exception.Create( 'Transaction is not active' );}
    if data_module.transaction.Active then
        data_module.transaction.Rollback;
end ;

procedure tSQLiteManager.SetParam( const pname: string; const pvalue: string) ;
begin
    CheckParam( pname,ftString ).AsString := pvalue;
end ;

procedure tSQLiteManager.SetParam( const pname: string; const pvalue: LongInt) ;
begin
    CheckParam( pname,ftInteger ).AsInteger := pvalue;
end ;

procedure tSQLiteManager.SetParam( const pname: string; const pvalue: Double) ;
begin
    CheckParam( pname,ftFloat ).AsFloat := pvalue;
end ;

procedure tSQLiteManager.SetParam( const pname: string; const pvalue: boolean) ;
begin
    CheckParam( pname,ftBoolean ).AsBoolean := pvalue;
end ;

procedure tSQLiteManager.SetParam( const pname: string; const pvalue: TDateTime) ;
begin
    CheckParam( pname,ftFloat ).AsFloat := DateTimeToJulianDate( pvalue );
end ;

procedure tSQLiteManager.ClearParams;
begin
    data_module.query.Params.Clear;
end ;

procedure tSQLiteManager.Execute( const sql: string; const with_transaction: boolean = false ) ;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if with_transaction then
        self.StartTransaction;
    with data_module do
        begin
		    query.Close;
		    query.SQL.Text := sql;
		    query.ExecSQL;
		end ;
	if with_transaction then
        data_module.transaction.Commit;
end ;

procedure tSQLiteManager.Select( const sql: string) ;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    with data_module do
        begin
            query.Close;
            query.SQL.Text := sql;
            query.Open;
		end ;
end ;

procedure tSQLiteManager.First;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.query.Active then
        raise Exception.Create( 'Query is closed' );
    data_module.query.First;
end ;

function tSQLiteManager.Next( const rewind: boolean = false ): boolean;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.query.Active then
        raise Exception.Create( 'Query is closed' );
    if rewind then
        data_module.query.First
    else
        data_module.query.Next;
    result := not data_module.query.EOF;
end ;

function tSQLiteManager.FieldAsString( const field: string) : string;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.query.Active then
        raise Exception.Create( 'Query is closed' );
    result := data_module.query.FieldByName( field ).AsString;
end ;

function tSQLiteManager.FieldAsLongint( const field: string) : LongInt;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.query.Active then
        raise Exception.Create( 'Query is closed' );
    result := data_module.query.FieldByName( field ).AsLongint;
end ;

function tSQLiteManager.FieldAsBoolean( const field: string) : boolean;
const bool_values: set of char = ['1','0'];
var
    b: string;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.query.Active then
        raise Exception.Create( 'Query is closed' );
    b := data_module.query.FieldByName( field ).AsString;
    if ( length( b ) > 1 )
       or ( length( b ) < 1 )
       or ( not ( b[1] in bool_values ) ) then
       raise Exception.Create( 'Boolean field "' + field + '" contains wrong data'#13 + b );
    result := b = '1';
end ;

function tSQLiteManager.FieldAsDouble( const field: string) : double;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.query.Active then
        raise Exception.Create( 'Query is closed' );
    result := data_module.query.FieldByName( field ).AsFloat;
end ;

function tSQLiteManager.FieldIsNull( const field: string) : boolean;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.query.Active then
        raise Exception.Create( 'Query is closed' );
    result := data_module.query.FieldByName( field ).IsNull;
end ;

function tSQLiteManager.FieldAsDateTime( const field: string) : TDateTime;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.query.Active then
        raise Exception.Create( 'Query is closed' );
    result := JulianDateToDateTime( data_module.query.FieldByName( field ).AsFloat );
end ;

procedure tSQLiteManager.ReadBlob( const id: word; const strm: tStream) ;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not self._use_blobs then
        raise Exception.Create( 'Blobs are not enabled' );
    self._blob_manager.Read( id, strm );
end ;

function tSQLiteManager.WriteBlob( const strm: tStream; const id: word = 0; use_transaction: boolean = true ) : word;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not self._use_blobs then
        raise Exception.Create( 'Blobs are not enabled' );
    result := self._blob_manager.Write( strm, id, use_transaction );
end ;

procedure tSQLiteManager.ForeignKeys( const enable: boolean) ;
var
    reopen: boolean;
begin
    reopen := data_module.sqlite.Connected;
    if reopen then
        begin
            Rollback;
            if enable then
                begin
                    Select( 'pragma foreign_key_check' );
                    if Next( true ) then
                        raise Exception.Create( 'Foreign key check failed!' );
				end ;
		    data_module.sqlite.Close( true );
		end ;
	data_module.sqlite.Params.Clear;
    data_module.sqlite.Params.Add( 'foreign_keys=' + ifthen( enable, 'on', 'off' ) );
    if reopen then
        data_module.sqlite.Open;
end ;

initialization
    {$I sqlite_manager.lrs}
    data_module_unit.data_module := Tdata_module.Create( nil );
finalization
    data_module_unit.data_module.Free;

end.
