(*
* Efimov V.P.
* kote.kagbe@gmail.com
* 2020
*)

unit scope_container;

{$mode objfpc}{$H+}  
{$modeswitch advancedrecords}

interface

uses
    Classes, SysUtils;

type
    { tScopeContainer }

    generic tScopeContainer<T: tObject> = record
    private
        _obj: T;

        class operator initialize( var instance: tScopeContainer ); inline;
        class operator finalize( var instance: tScopeContainer ); inline;
    public
        // returns the stored object
        function get: T; inline;
        // frees the stored object
        procedure reset; inline;

        class operator := ( const value: T ): tScopeContainer; inline;
        class operator := ( const instance: tScopeContainer ): boolean; inline;
        class operator not ( const instance: tScopeContainer ): boolean; inline;
    end ;

implementation

{ tScopeContainer }

class operator tScopeContainer.initialize ( var instance: tScopeContainer ) ;
begin
    instance._obj := default( T );
end ;

class operator tScopeContainer.finalize ( var instance: tScopeContainer ) ;
begin
    instance.reset;
end ;

function tScopeContainer.get: T;
begin
    result := _obj;
end ;

procedure tScopeContainer.reset;
begin
    if assigned( _obj ) then
    begin
        _obj.Free;
        _obj := default( T );
    end ;
end ;

class operator tScopeContainer. := ( const value: T ) : tScopeContainer;
begin
    result.reset;
    result._obj := value;
end ;

class operator tScopeContainer. := ( const instance: tScopeContainer ) : boolean;
begin
    result := Assigned( instance._obj );
end ;

class operator tScopeContainer.not ( const instance: tScopeContainer) : boolean;
begin
    result := not Assigned( instance._obj );
end ;

end .

