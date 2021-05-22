unit shared_lock;

{$mode objfpc}{$H+}
{$ModeSwitch advancedrecords}

interface

uses
    Classes, SysUtils, syncobjs;

type

    { tSharedLock }

    tSharedLock = class
    private
        _lock: TCriticalSection;
        _counter: integer;

    public
        constructor Create;
        destructor Destroy; override;
    end;

    { tWriteLock }

    tWriteLock = record
    private
        _lock: tSharedLock;
        _locked: boolean;

        class operator initialize( var instance: tWriteLock ); inline;
        class operator finalize( var instance: tWriteLock ); inline;
    public
        procedure Acquire( var lock: tSharedLock );
        procedure Release;
    end;

    { tReadLock }

    tReadLock = record
    private
        _lock: tSharedLock;
        _locked: boolean;

        class operator initialize( var instance: tReadLock ); inline;
        class operator finalize( var instance: tReadLock ); inline;
    public
        procedure Acquire( var lock: tSharedLock );
        procedure Release;
    end ;

implementation

{ tWriteLock }

class operator tWriteLock.initialize ( var instance: tWriteLock ) ;
begin
    instance._lock := nil;
    instance._locked := false;
end ;

procedure tWriteLock.Acquire ( var lock: tSharedLock );
begin
    if _locked then
        exit;
    _lock := lock;
    repeat
        _lock._lock.Acquire;
        _locked := _lock._counter = 0;
        if not _locked then
            _lock._lock.Release;
    until _locked;
    _lock._counter := -1;
    _lock._lock.Release;
end ;

procedure tWriteLock.Release;
begin
    if _lock = nil then
        exit;
    if not _locked then
        exit;
    _lock._lock.Acquire;
    _locked := false;
    _lock._counter := 0;
    _lock._lock.Release;
    _lock := nil;
end ;

class operator tWriteLock.finalize ( var instance: tWriteLock ) ;
begin
    if instance._lock <> nil then
        instance.Release;
end ;

{ tReadLock }

class operator tReadLock.initialize ( var instance: tReadLock ) ;
begin
    instance._lock := nil;
    instance._locked := false;
end ;

procedure tReadLock.Acquire ( var lock: tSharedLock ) ;
begin
    if _lock <> nil then
        exit;
    if _locked then
        exit;
    _lock := lock;
    repeat
        _lock._lock.Acquire;
        _locked := ( _lock._counter >= 0 );
        if not _locked then
            _lock._lock.Release;
    until _locked;
    _lock._counter += 1;
    _lock._lock.Release;
end ;

procedure tReadLock.Release;
begin
    if _lock = nil then
        exit;
    if not _locked then
        exit;
    _lock._lock.Acquire;
    _locked := false;
    _lock._counter -= 1;
    _lock._lock.Release;
    _lock := nil;
end ;

class operator tReadLock.finalize ( var instance: tReadLock ) ;
begin
    if instance._lock <> nil then
        instance.Release;
end ;

{ tSharedLock }

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

