(*
* Efimov V.P.
* kote.kagbe@gmail.com
* 2020
*)

unit optional;

{$mode objfpc}{$H+}
{$modeSwitch advancedRecords}

interface

uses
    Classes, SysUtils;

type

    // special exception types
    // raised in case of calling Get() over empty state
    eEmptyOptional = class( Exception );
    // (streaming)
    // raised in case of too big data for writing
    eOptionalOversize = class( Exception );

    // data storage structure
    generic tOptionalData<T> = record
        _isSet: boolean;
        _value: T;
    end;

    // basic generic type
    generic tOptional<T> = record
    type 
        // data storage specialization
        tOptionalDataImpl = specialize tOptionalData<T>;
        // (streaming)
        // typedef for streaming restriction
        tMaxDataSizeType = type word;
    private
        // data storage
        _data: tOptionalDataImpl;

        // (streaming)
        // max allowed for streaming(!) data size
        const MAX_DATA_SIZE = high( tMaxDataSizeType );

        // (streaming)
        // returns full data size
        // must be overloaded for complex types
        function DataSize: longint; inline;

        // constructor
        class operator Initialize( var instance: tOptional ); inline;
    public
        // returns stored data if it is set and raises eEmptyOptional otherwise
        function Get: T; inline;
        // returns stored data if it is set and passed value otherwise
        function Get( default_value: T ): T; overload; inline;
        // resets to "not set" state
        procedure Reset; inline;

        // (streaming)
        // streaming capabilities
        procedure Read( const strm: tStream ); inline;
        procedure Write( const strm: tStream ); inline;

        // operators for easy use
        // assignment
        class operator := ( const value: T ): tOptional; inline;
        // is (not)set check
        // if opt_var then ...
        class operator := ( const instance: tOptional ): boolean; inline;
        // if not opt_var then ...
        class operator not ( const instance: tOptional ): boolean; inline;
        // comparison
        // if opt1 = opt2 then ...
        class operator = ( const inst1, inst2: tOptional ): boolean; inline;
        // if opt = val then ...
        class operator = ( const instance: tOptional; const value: T ): boolean; inline;
        class operator = ( const value: T; const instance: tOptional ): boolean; inline;
    end;

    // some basic types ready
    tOptString = specialize tOptional<string>;
    tOptInteger = specialize tOptional<integer>;
    tOptReal = specialize tOptional<real>;
    tOptBoolean = specialize tOptional<boolean>;

    // (streaming)
    // helper for overloading data size calculation
    // since '' is a valid set value
    tOptStringHelper = record helper for tOptString
    private
        function DataSize: longint;
    end;

implementation

{tOptional}

class operator tOptional.Initialize( var instance: tOptional );
begin
    with instance._data do
    begin
        _isSet := false;
        _value := default( T );
    end;
end;

class operator tOptional. := ( const value: T ): tOptional;
begin
    with result._data do
    begin
        _isSet := true;
        _value := value;
    end;
end;

class operator tOptional. := ( const instance: tOptional ): boolean;
begin
    result := instance._data._isSet;
end;

class operator tOptional. not ( const instance: tOptional ): boolean;
begin
    result := not instance._data._isSet;
end;

class operator tOptional. = ( const inst1, inst2: tOptional ): boolean;
begin
    result := boolean( inst1 ) and boolean( inst2 ) and ( inst1.get = inst2.get );
end;

class operator tOptional. = ( const instance: tOptional; const value: T ): boolean;
begin
    result := boolean( instance ) and ( instance.get = value )
end;

class operator tOptional. = ( const value: T; const instance: tOptional ): boolean;
begin
    result := boolean( instance ) and ( instance.get = value )
end;

function tOptional.Get: T;
begin
    if not _data._isSet then
        raise eEmptyOptional.Create( 'Optional is empty' )
    else
        result := _data._value;
end;

function tOptional.Get( default_value: T ): T;
begin
    if not _data._isSet then
        result := default_value
    else
        result := _data._value;
end;

procedure tOptional.Reset;
begin
    with self._data do
    begin
        _isSet := false;
        _value := default( T );
    end;
end;

{streaming}

procedure tOptional.Read( const strm: tStream );
var
    size: tMaxDataSizeType = default( tMaxDataSizeType );
begin
    Reset;
    strm.Read( size, sizeof( size ) );
    if size > 0 then
        strm.Read( _data, size );
end;

procedure tOptional.Write( const strm: tStream );
var
    size: tMaxDataSizeType = default( tMaxDataSizeType );
    _size: longint;
begin
    _size := DataSize;
    if _size > MAX_DATA_SIZE then
        raise eOptionalOversize.Create( 'Optional data is too big' );
    size := tMaxDataSizeType( _size );
    strm.Write( size, sizeof( size ) );
    if size > 0 then
        strm.Write( _data, size );
end;

function tOptional.DataSize: longint;
begin
    if _data._isSet then
        result := sizeof( _data )
    else 
        result := 0;
end;

function tOptStringHelper.DataSize: longint;
begin
    if not _data._isSet then
        result := 0
    else
        result := ( length( _data._value ) * sizeof( _data._value[1] ) ) + sizeof( _data._isSet );
end;

end.

