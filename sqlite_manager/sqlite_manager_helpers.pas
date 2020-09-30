unit sqlite_manager_helpers;

{$mode objfpc}{$H+}

interface

uses
    SysUtils, sqlite_manager, optional, data_module_unit;

type

    { tSQLiteManagerHelper }
    (*
        couldn't compile with this method in sqlite_manager unit
        so when you need to call it you need to add to uses clause
        sqlite_manager_helpers and optional
        call like
        my_opt_var := SQLiteManager_var.specialize FieldAsOptional<my_type>( 'field_name' );
    *)

    tSQLiteManagerHelper = class helper for tSQLiteManager
    public
        generic function FieldAsOptional<T>( const field: string ): specialize tOptional<T>;
    end ;

implementation
uses Variants;

{ tSQLiteManagerHelper }

generic function tSQLiteManagerHelper.FieldAsOptional<T>( const field: string ): specialize tOptional<T>;
var
    value: Variant;
begin
    if not data_module.sqlite.Connected then
        raise Exception.Create( 'Database is not connected' );
    if not data_module.query.Active then
        raise Exception.Create( 'Query is closed' );
    value := data_module.query.FieldByName( field ).AsVariant;
    result.Reset;
    if not( VarIsClear( Value ) or VarIsEmpty( Value ) or VarIsNull( Value ) or ( VarCompareValue( Value, Unassigned ) = vrEqual ) ) then
        result := T( value );
end ;

end .

