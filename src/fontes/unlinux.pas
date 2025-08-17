unit unLinux;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, 
  SysUtils, 
  BaseUnix, 
  Unix, 
  SyncObjs;

type
  TPosixSignal = (Termination, Reload, User1, User2);
  TSignalProc = procedure(Sig: TPosixSignal);
  TProc = procedure of object;

  { TPosixDaemon }

  TPosixDaemon = class
  private
    class var FSignalProc: TSignalProc;
    class var FRunningEvent: TEvent;
    class procedure CathHandleSignals;
  public const
    EXIT_SUCESS = 0;
    EXIT_FAILURE = 1;
  public
    class procedure CreatePIDFile(const APAth: String);
    class procedure RemovePIDFile(const APath: String);
    class procedure Setup(ASignalProc: TSignalProc);
    class procedure Run(const AInterval: Integer; PProc: TProc);
  end;

procedure TratarSinais(ASigNum: TPosixSignal);
procedure sd_notify(unused: cint; state: PChar); cdecl; external 'libsystemd.so';

implementation

procedure TratarSinais(ASigNum: TPosixSignal);
begin
   case ASigNum of
    Termination: Writeln('Entrou no term');
    Reload: Writeln('Entrou no reload');
    User1: Writeln('Entrou no usr1');
    User2: Writeln('Entrou no usr2');
  end;
end;

procedure HandleSignals(ASigNum: cint); cdecl;
begin
  case ASigNum of
    SIGTERM:
    begin
      TPosixDaemon.FSignalProc(TPosixSignal.Termination);
      TPosixDaemon.RemovePIDFile('');
      TPosixDaemon.FRunningEvent.SetEvent;
    end;
    SIGHUP:
    begin
      TPosixDaemon.FSignalProc(TPosixSignal.Reload);
    end;
    SIGUSR1:
    begin
      TPosixDaemon.FSignalProc(TPosixSignal.User1);
      TPosixDaemon.FRunningEvent.SetEvent;
    end;
    SIGUSR2: TPosixDaemon.FSignalProc(TPosixSignal.User2);
  end;
end;

{ TPosixDaemon }

class procedure TPosixDaemon.CathHandleSignals;
begin
  FpSignal(SIGHUP, @HandleSignals);
  FpSignal(SIGTERM, @HandleSignals);
  FpSignal(SIGUSR1, @HandleSignals);
  FpSignal(SIGUSR2, @HandleSignals);
end;

class procedure TPosixDaemon.CreatePIDFile(const APAth: String);
var
  liPID: Integer;
  lsPath: String;
  lFile: Text;
begin
  liPID:= FpGetpid;

  if (liPID > 0) then
  begin
    lsPath:= '/run/' + ExtractFileName(ParamStr(0)) + '.pid';
    if (Trim(APath) <> '') then
       lsPath:= APath;

    try
      if (FileExists(lsPath)) then
         DeleteFile(lsPath);

      AssignFile(lFile, lsPath);
      Rewrite(lFile);
      WriteLn(lFile, IntToStr(liPID));
      CloseFile(lFile);
    except
    end;
  end;
end;

class procedure TPosixDaemon.RemovePIDFile(const APath: String);
var
  lsPath: String;
begin
  try
    lsPath:= '/run/' + ExtractFileName(ParamStr(0)) + '.pid';
    if (Trim(APath) <> '') then
       lsPath:= APath;

    if (FileExists(lsPath)) then
       DeleteFile(lsPath);
  except
  end;
end;

class procedure TPosixDaemon.Setup(ASignalProc: TSignalProc);
begin
  FSignalProc:= ASignalProc;

  CathHandleSignals;
end;

class procedure TPosixDaemon.Run(const AInterval: Integer; PProc: TProc);
begin
  sd_notify(0, 'READY=1');

  FRunningEvent:= TEvent.Create(nil, True, False, '');
  try
    while FRunningEvent.WaitFor(AInterval) <> wrSignaled do
    begin
      if (Assigned(PProc)) then
         PProc;
    end;
  finally
    FreeAndNil(FRunningEvent);
  end;
end;

end.

