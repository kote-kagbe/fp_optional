unit network_updater;

{$mode objfpc}{$H+}

interface

uses base_updater;

type
    tProxyInfo = record
        address: string;
        port: string;
        user: string;
        password: string;
    end;

    tNetworkUpdater = class( tBaseUpdater )
    protected
        _proxy: tProxyInfo;
    public
        property proxy: tProxyInfo read _proxy;
    end;

implementation

end.