unit json_api_updater;

{$mode objfpc}{$H+}

interface

uses classes, http_updater, fpjson, sysutils;

type
    tArrayOfString = array of string;
    tJSONTypesArray = array of tJSONType;

    tJSONAPIUpdater = class( tHTTPUpdater )
    protected
        generic function valid_json <T:tJSONData> ( const j: tJSONData ): boolean;
        function valid_json_object( const j: tJSONData; const fields: tArrayOfString = nil; field_types: tJSONTypesArray = nil ): boolean;
        function valid_json_array( const j: tJSONData ): boolean;
    
    end;

implementation

generic function tJSONAPIUpdater.valid_json<T>( const j: tJSONData ): boolean;
begin
    result := ( j <> nil ) and ( j is T ) and ( not( j.IsNull ) );
end;

function tJSONAPIUpdater.valid_json_object( const j: tJSONData; const fields: tArrayOfString; field_types: tJSONTypesArray ): boolean;
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

function tJSONAPIUpdater.valid_json_array( const j: tJSONData ): boolean;
begin
    result := specialize valid_json<tJSONArray>( j );
end;

end.