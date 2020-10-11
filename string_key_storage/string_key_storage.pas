unit string_key_storage;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
    Classes, SysUtils, optional, syncobjs;

type

    { tSKSNodeRec }

    generic tSKSNodeRec<ValueType> = record
    private
        _key: specialize tOptional<char>;
        _value: specialize tOptional<ValueType>;
        _key_count: word;
        _next: ^specialize tSKSNodeRec<ValueType>;
        _sibling: ^specialize tSKSNodeRec<ValueType>;
        _ref_count: byte;
        _locker: TCriticalSection;

        class operator initialize( var instance: tSKSNodeRec ); inline;
        class operator finalize( var instance: tSKSNodeRec ); inline;
    public
        constructor Init( const key: char );
    end;

    { tItemLocker }

    generic tItemLocker<ValueType> = record
    type
        _tSKSNodeRec = specialize tSKSNodeRec<ValueType>;
        _pSKSNodeRec = ^_tSKSNodeRec;
    private
        _value: _pSKSNodeRec;
        class operator initialize( var instance: tItemLocker ); inline;
        class operator finalize( var instance: tItemLocker ); inline;
    public
        class operator := ( const value: _pSKSNodeRec ): tItemLocker; inline;
    end;

    generic tOnReleaseNode<ValueType> = procedure( const value: ValueType ) of object;

    { tStringKeyStorage }

    generic tStringKeyStorage<ValueType> = class
    type
        _tOnReleaseNode = specialize tOnReleaseNode<ValueType>;
        _tSKSNodeRec = specialize tSKSNodeRec<ValueType>;
        _pSKSNodeRec = ^_tSKSNodeRec;
    protected
        _root: _pSKSNodeRec;

        _onReleaseNode: _tOnReleaseNode;

        procedure releaseNode( const node: _tSKSNodeRec ); virtual;
        function Get( const key: string ): _pSKSNodeRec; overload;
        function Get( const node: _pSKSNodeRec; out value: ValueType ): boolean; overload;
    public
        constructor Create;

        procedure Add( const key: string; const value: ValueType );
        function Get( const key: string; out value: ValueType ): boolean; overload;
        function Get( const key: string; out value: ValueType; var locker: specialize tItemLocker<ValueType> ): boolean; overload;
        //procedure Remove( const key: string );

        procedure list( const key: string );

        property onReleaseNode: _tOnReleaseNode write _onReleaseNode;
    end;

    // generic tSequenceKeyObjectStorage<KeyType, KeyElementType, ValueType: tObject> = class( specialize tSequenceKeyStorage<KeyType, KeyElementType, ValueType> )
    // protected
    //     procedure releaseNode; override;
    // end;

implementation

{ tItemLocker }

class operator tItemLocker.initialize ( var instance: specialize tItemLocker<ValueType> ) ;
begin
    instance._value := default( _pSKSNodeRec );
end ;

class operator tItemLocker.finalize ( var instance: tItemLocker ) ;
begin
    if instance._value <> nil then
        begin
            instance._value^._locker.Acquire;
            instance._value^._ref_count -= 1;
            if( instance._value^._ref_count = 0 )and( not instance._value^._key ) then
                dispose( instance._value )
            else
                instance._value^._locker.Release;
        end ;
end ;

class operator tItemLocker. := ( const value: _pSKSNodeRec ) : tItemLocker;
begin
    if value = nil then
        exit;
    value^._locker.Acquire;
    result._value := value;
    result._value^._ref_count += 1;
    result._value^._locker.Release;
end ;

class operator tSKSNodeRec.initialize( var instance: tSKSNodeRec );
begin
    instance._key_count := 0;
    instance._next := nil;
    instance._sibling := nil;
    instance._value := default( ValueType );
    instance._ref_count := 0;
    instance._locker := TCriticalSection.Create;
end;

class operator tSKSNodeRec.finalize ( var instance: tSKSNodeRec ) ;
begin
    instance._locker.Free;
end ;

constructor tSKSNodeRec.Init( const key: char );
begin
    _key := key;
    //_key_count += 1;
end;

procedure tStringKeyStorage.list( const key: string );
var
    id: char;
begin
    for id in key do
       // writeln(id);
end;

constructor tStringKeyStorage.Create;
begin
    _onReleaseNode := nil;
    
end;

procedure tStringKeyStorage.releaseNode( const node: _tSKSNodeRec );
begin
  
    if( Assigned( _onReleaseNode ) )and( boolean( node._value ) )then
        _onReleaseNode( node._value.get );
end;

procedure tStringKeyStorage.Add( const key: string; const value: ValueType );
var
    id: char;
    node, current_node: _pSKSNodeRec;
    n, l: word;
begin
    current_node := _root;
    node := nil;
    n := 0; // key item pos
    l := length( key );
    for id in key do
        begin
            n += 1;
            // current node is empty
            if current_node = nil then
                begin
                    // empty root item
                    if node = nil then
                        begin
                            // creating new
                            _root := new( _pSKSNodeRec );
                            _root^.Init( id );
                            current_node := _root;
                            // adding to the current key chain
                            current_node^._key_count += 1;
                            // creating empty _next for the next key item
                            if n < l then
                                begin
                                    node := new( _pSKSNodeRec );
                                    current_node^._next := node;
                                    current_node := current_node^._next;
                                end;
                            node := nil;
                        end
                    // empty _next value, node == previous current_key
                    else
                        begin
                            // creating new
                            current_node := new( _pSKSNodeRec );
                            current_node^.Init( id );
                            // adding to the current key chain
                            current_node^._key_count += 1;
                            // updating previous key
                            node^._next := current_node;
                            node := nil;
                        end;
                end
            // key item is not filled - it was created on the previous step for current key item
            else if not current_node^._key then
                begin
                    // filling
                    current_node^.Init( id );
                    // adding to the current key chain
                    current_node^._key_count += 1;
                    // creating _next
                    if n < l then
                        begin
                            node := new( _pSKSNodeRec );
                            current_node^._next := node;
                            current_node := current_node^._next;
                        end;
                    node := nil;
                end
            // current key is equal with the current key item
            else if current_node^._key = id then
                begin
                    // adding to the current key chain
                    current_node^._key_count += 1;
                    // switching to the next key item
                    node := current_node;
                    if n < l then
                        current_node := current_node^._next;
                end
            // current key does not fit the current key item
            else
                begin
                    // walking through the key siblings
                    node := current_node^._sibling;
                    while( node <> nil )and( node^._key <> id ) do
                        begin
                            current_node := node;
                            node := node^._sibling;
                        end;
                    // no sibling is equal the current key item
                    if node = nil then
                        begin
                            // creating new
                            node := new( _pSKSNodeRec );
                            // filling with current key item
                            node^.Init( id );
                            // adding sibling to the current node
                            current_node^._sibling := node;
                            // switching to it
                            current_node := node;
                            // adding it to the current key chain
                            current_node^._key_count += 1;
                            // creating _next
                            if n < l then
                                begin
                                    node := new( _pSKSNodeRec );
                                    current_node^._next := node;
                                    current_node := current_node^._next;
                                end;
                            node := nil;
                        end
                    // found sibling with current key item
                    else
                        begin
                            // adding to current key chain
                            node^._key_count += 1;
                            // switching to the next key item
                            node := current_node;
                            if n < l then
                                current_node := node^._next
                            else
                                current_node := node;
                        end;
                end;
        end;
    if( assigned( _onReleaseNode ) )and( boolean( current_node^._value ) ) then
        _onReleaseNode( current_node^._value.get );
    current_node^._value := value;
end;

function tStringKeyStorage.Get ( const key: string ) : _pSKSNodeRec;
var
    current_node: _pSKSNodeRec;
    id: char;
    l, n: word;
begin
    result := nil;
    l := length( key );
    writeln( 'key length ', l );
    n := 0;
    current_node := _root;
    for id in key do
        begin
            n += 1;
            if current_node = nil then
                begin
                    writeln( id, n, ' node is empty' );
                    break;
                end
            else if current_node^._key = id then
                begin
                    writeln( id, n, ' node found' );
                    if n < l then
                        begin
                            writeln( id, n, ' next' );
                            current_node := current_node^._next;
                        end;
                    continue
                end
            else
                begin
                    writeln( id, n, ' parsing siblings' );
                    current_node := current_node^._sibling;
                    while ( current_node <> nil )and( current_node^._key <> id ) do
                        begin
                            writeln( id, n, ' sibling' );
                            current_node := current_node^._sibling;
                        end;
                    if current_node = nil then
                        begin
                            writeln( id, n, ' sibling NOT found' );
                            break;
                        end
                    else
                        writeln( id, n, ' sibling found' );
                    if n < l then
                        begin
                            writeln( id, n, ' next' );
                            current_node := current_node^._next;
                        end;
                end;
        end;
    if ( current_node <> nil )and( boolean( current_node^._value ) ) then
        begin
            writeln( id, n, ' value found' );
            result := current_node;
        end
    else
        writeln( id, n, ' value NOT found' );
end ;

function tStringKeyStorage.Get ( const node: _pSKSNodeRec; out value: ValueType ) : boolean;
begin
    value := default( ValueType );
    result := node <> nil;
    if result then
        value := node^._value;
end ;

function tStringKeyStorage.Get( const key: string; out value: ValueType ): boolean;
begin
    result := Get( Get( key ), value );
end;

function tStringKeyStorage.Get( const key: string; out value: ValueType; var locker: specialize tItemLocker<ValueType> ): boolean;
var
    node: _pSKSNodeRec;
begin
    node := Get( key );
    result := Get( node, value );
    if result then
        locker := node;
end ;

{procedure tStringKeyStorage.Remove( const key: _KeyType );
begin
    
end;}

// procedure tStringKeyStorage.releaseNode;
// begin
  
// end;

end.

