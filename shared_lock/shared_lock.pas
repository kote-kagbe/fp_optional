unit shared_lock;

{$mode objfpc}{$H+}
{$ModeSwitch advancedrecords}

interface

uses
    Classes, SysUtils, syncobjs, optional;

type
    tWriteID = specialize tOptional<longint>;

    { tSharedLock }

    tSharedLock = class
    strict private
        _write_id: tWriteID;
    private
        _lock: TCriticalSection;
        _counter: integer;

        function get_write_id: tWriteID;
        procedure reset_write_id;
    public
        constructor Create;
        destructor Destroy; override;
    end;

    { tWriteLock }

    tWriteLock = record
    private
        _lock: tSharedLock;
        _id: tWriteID;
    public
        function Acquire( var lock: tSharedLock ): tWriteID;
        procedure Release;
        class operator finalize( var instance: tWriteLock ); inline;
    end;

    { tReadLock }

    tReadLock = record
    private
        _lock: tSharedLock;
    public
        procedure Acquire( var lock: tSharedLock; const id: tWriteID ); overload;
        procedure Acquire( var lock: tSharedLock ); overload;
        procedure Release;

        class operator finalize( var instance: tReadLock ); inline;
    end ;

implementation

{ tWriteLock }

function tWriteLock.Acquire ( var lock: tSharedLock ) : tWriteID;
var
    locked: boolean;
begin
    _lock := lock;
    locked := false;
    repeat
        _lock._lock.Acquire;
        locked := _lock._counter = 0;
        if not locked then
            _lock._lock.Release;
    until locked;
    _id := _lock.get_write_id;
    result := _id;
    _lock._counter := -1;
    _lock._lock.Release;
end ;

procedure tWriteLock.Release;
var
    locked: boolean;
begin
    if _lock = nil then
        exit;
    locked := false;
    repeat
        _lock._lock.Acquire;
        locked := ( _lock._counter = -1 )and( _lock.get_write_id = _id );
        if not locked then
            _lock._lock.Release;
    until locked;
    _lock.reset_write_id;
    _lock._counter := 0;
    _lock := nil;
    _id.Reset;
    _lock._lock.Release;
end ;

class operator tWriteLock.finalize ( var instance: tWriteLock ) ;
begin
    if instance._lock <> nil then
        instance.Release;
end ;

{ tReadLock }

procedure tReadLock.Acquire ( var lock: tSharedLock; const id: tWriteID ) ;
var
    locked: boolean;
begin
    _lock := lock;
    locked := false;
    repeat
        _lock._lock.Acquire;
        locked := ( _lock._counter >= 0 )or( _lock.get_write_id = id );
        if not locked then
            _lock._lock.Release;
    until locked;
    _lock._counter += 1;
    _lock._lock.Release;
end ;

procedure tReadLock.Acquire ( var lock: tSharedLock ) ;
var
    tmp: tWriteID;
begin
    Acquire( lock, tmp );
end ;

procedure tReadLock.Release;
var
    locked: boolean;
begin
    if _lock = nil then
        exit;
    locked := false;
    repeat
        _lock._lock.Acquire;
        locked := _lock._counter > 0;
        if not locked then
            _lock._lock.Release;
    until locked;
    _lock._counter -= 1;
    _lock := nil;
    _lock._lock.Release;
end ;

class operator tReadLock.finalize ( var instance: tReadLock ) ;
begin
    if instance._lock <> nil then
        instance.Release;
end ;

{ tSharedLock }

function tSharedLock.get_write_id: tWriteID;
begin
    if not _write_id then
        _write_id := random( high( longint ) );
    result := _write_id;
end ;

procedure tSharedLock.reset_write_id;
begin
    _write_id.Reset;
end ;

constructor tSharedLock.Create;
begin
    _lock := TCriticalSection.Create;
    _counter := 0;
end ;

destructor tSharedLock.Destroy;
begin
    _lock.Free;
    inherited Destroy;
end ;

initialization
    randomize;

end .

