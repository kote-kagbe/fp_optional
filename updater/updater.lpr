program updater;
{$mode objfpc}{$H+}

uses classes, base_updater, googledrive_updater, yandexdisk_updater, ftp_updater, local_updater,
     fileutil, sysutils, fgl;

type
    rec = record
      a,b:string;
    end ;

    map = specialize tfpgmap<string,rec>;


var
    o: tUpdaterOptions;
    u:tBaseUpdater;
    s:string;
    i:integer=123;
    m: map;
    r: rec;

procedure ilog( const message_text: string; const message_type: tLogMessageType = lmtMESSAGE );
begin
    writeln(message_text);
end;

procedure test(const rr:rec);
begin
    rr.a:='aa';
end;

begin

o.log_processor := @ilog;
o.source := 'src';
o.destination := 'dst';
//o.storage:='c:\temp\';

u := tLocalUpdater.create(o);


deletefile('asdas');
writeln(SysErrorMessage(GetLastOSError));
readln;

m := map.Create;
r.a:='a'; r.b:='b';
m.add('0',r);
test(m.Data[0]);
writeln(m.data[0].a);

end.

