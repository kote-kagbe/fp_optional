unit local_updater;

{$mode objfpc}{$H+}

interface

uses base_updater, classes, scope_container;

type
    tLocalUpdater = class( tBaseUpdater )
    protected
        function FetchRemoteFilesInfo: boolean; override;
        function FetchFile( const path: string; const strm: tStream ): boolean; override;
    
    end;

implementation

function tLocalUpdater.FetchRemoteFilesInfo: boolean;
begin

end;

function tLocalUpdater.FetchFile( const path: string; const strm: tStream ): boolean;
var
    source: specialize tScopeContainer<tFileStream>;
begin

end;

end.