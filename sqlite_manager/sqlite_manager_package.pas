{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit sqlite_manager_package;

{$warn 5023 off : no warning about unused units}
interface

uses
    data_module_unit, sqlite_manager, database_converter_unit, 
    blob_manager_unit, optional, sqlite_manager_helpers, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit ( 'sqlite_manager', @sqlite_manager.Register ) ;
end ;

initialization
  RegisterPackage ( 'sqlite_manager_package', @Register ) ;
end .
