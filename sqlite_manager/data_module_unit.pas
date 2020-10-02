(*
* Efimov V.P.
* kote.kagbe@gmail.com
* 2020
*)

unit data_module_unit;

{$mode objfpc}{$H+}

interface

uses
        Classes, SysUtils, sqldb, sqlite3conn;

type

		{ Tdata_module }

        Tdata_module = class ( TDataModule)
				sqlite: TSQLite3Connection;
				query: TSQLQuery;
				transaction: TSQLTransaction;
				procedure sqliteAfterConnect( Sender: TObject) ;
        private

        public

        end ;

var
        data_module: Tdata_module;

implementation

{$R *.lfm}

{ Tdata_module }

procedure Tdata_module.sqliteAfterConnect( Sender: TObject) ;
begin
    {
        foreign_keys=on moved to sqlite.Params
        http://forum.lazarus.freepascal.org/index.php?topic=15477.0
        https://bugs.freepascal.org/view.php?id=20865
    }
    //sqlite.Transaction.EndTransaction;
    //sqlite.ExecuteDirect( 'PRAGMA foreign_keys = ON;' );
    //sqlite.Transaction.Commit;
end;

end .

