(*
* Efimov V.P.
* kote.kagbe@gmail.com
* 2020
*)

unit md5_stream;

{$mode objfpc}{$H+}

interface

uses
    Classes, SysUtils, md5;

function MD5Stream( const strm: tStream; const Bufsize: PtrUInt = MDDefBufSize ): TMD5Digest;

implementation

function MD5Stream( const strm: tStream; const Bufsize: PtrUInt) : TMD5Digest;
var
  Buf: Pchar;
  Context: TMDContext;
  Count: Cardinal;
begin
    MDInit( Context, MD_VERSION_5 );

	GetMem( Buf, BufSize );

	repeat
        count := strm.Read( buf^, Bufsize );
	    if Count > 0 then
	        MDUpdate( Context, Buf^, Count );
	until Count < BufSize;

	FreeMem( Buf, BufSize );

    MDFinal(Context, Result);
end;

end .

