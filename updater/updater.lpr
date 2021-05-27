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
    u: tBaseUpdater;
    f: text;
    b: boolean;
    m: map;

procedure ilog( const message_text: string; const message_type: tLogMessageType = lmtMESSAGE );
begin
    write(message_text);
    write(f,message_text);
end;

begin

assignfile(f,'log.txt');
rewrite(f);

o.log_processor := @ilog;
{$ifdef darwin}
o.source := '/Users/efimovvp/Documents/tmp/source';
o.destination := '/Users/efimovvp/Documents/tmp/target';
o.storage := '/Users/efimovvp/Documents/tmp/updates';
{$else}

{$endif}

u := tLocalUpdater.create(o);

try
    b := u.CheckUpdates = crOUTDATED;
    writeln( 'check result ', b );
    if b then
        b := u.FetchUpdates = frOK;
    writeln( 'fetch result ', b );
    if b then
        b := u.ApplyUpdates = arOK;
    writeln( 'apply result ', b );
    if b then
        u.cleanup;
    writeln( 'cleanup result ', b );
except on exc: Exception do
    writeln( 'ERROR ' + exc.message );
end;

u.free;

closefile(f);

m := map.create;
m.Duplicates := dupignore;
m.sorted := true;
m.add( 'asd' );
m.add( 'asd' );
m.add( 'asd' );
m.add( 'asd' );
writeln( m.count );
m.free;

end.

// fpc updater.lpr -Si -gh -Fu../scope_container -Fu../md5_stream -Fu/Library/Lazarus/components/lazutils/lib/x86_64-darwin
// ./updater