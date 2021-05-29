program updater;
{$mode objfpc}{$H+}

uses classes, base_updater, googledrive_updater, yandexdisk_updater, ftp_updater, local_updater,
     fileutil, sysutils, fgl, dateutils;

type
    rec = record
      a,b:string;
    end ;

    map = specialize tfpgmap<string,string>;

    array_of_string = array of string;

var
    o: tUpdaterOptions;
    u: tBaseUpdater;
    //f: text;
    b: boolean;
    m: map;
    dt: tDatetime;
    fs:tfilestream;

procedure ilog( const message_text: string; const message_type: tLogMessageType = lmtMESSAGE );
begin
    write(message_text);
    fs.write( message_text[1], length(message_text) );
    //write(f,message_text);
end;

procedure slog( const data: tStream; const message_type: tLogMessageType = lmtMESSAGE );
var p: int64;
begin
    p:=data.position;
    data.seek(0,sofrombeginning);
    fs.copyfrom(data,data.size-data.position);
    data.seek(p,sofrombeginning);
end;

procedure aos( q: array_of_string = nil );
var 
s:string;
begin
writeln('->()');
writeln(length(q));
    for s in q do writeln(s);
writeln('()->');
end;

begin

//assignfile(f,'log.txt');
//rewrite(f);
fs:=tfilestream.create( 'log.txt', fmcreate );

o.log_processor := @ilog;
o.stream_log_processor := @slog;
{$ifdef darwin}
o.source := '1HHGu_grNVwwsUWIadA8eVd9cTjQiFhVl'; //'/Users/efimovvp/Documents/tmp/source';
o.destination := '/Users/efimovvp/Documents/tmp/target';
o.storage := '/Users/efimovvp/Documents/tmp/updates';
{$else}
o.source := '1HHGu_grNVwwsUWIadA8eVd9cTjQiFhVl'; //'T:\temp\updater\source';
o.destination := 'T:\temp\updater\target';
o.storage := 'T:\temp\updater\storage';
{$endif}


u := tGoogleDriveUpdater.create(o);

try
    b := u.CheckUpdates = crOUTDATED;
    writeln( 'check result ', b );
    {if b then
        b := u.FetchUpdates = frOK;
    writeln( 'fetch result ', b );
    if b then
        b := u.ApplyUpdates = arOK;
    writeln( 'apply result ', b );
    if b then
        u.cleanup;
    writeln( 'cleanup result ', b );}
except on exc: Exception do
    writeln( 'ERROR ' + exc.message );
end;

u.free;


//closefile(f);
fs.free;

readln;

end.

// fpc updater.lpr -Si -gh -Fu../scope_container -Fu../md5_stream -Fu/Library/Lazarus/components/lazutils/lib/x86_64-darwin -Fu../synapse40/source/lib -Fu/opt/fpc-3.0.4/packages/fcl-json/src
// ./updater
// https://drive.google.com/drive/folders/1HHGu_grNVwwsUWIadA8eVd9cTjQiFhVl?usp=sharing
// 1HHGu_grNVwwsUWIadA8eVd9cTjQiFhVl
