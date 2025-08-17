program Rinha;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, CustApp,
  unLinux, unServer, unGenerica, unAPI, unRequisicaoPendente, unPersistencia
  { you can add units after this };

type

  { TRinha }

  TRinha = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

{ TRinha }

procedure TRinha.DoRun;
begin
  { add your program here }
  {$IFDEF SERVICO}
    if (Trim(UpperCase(Copy(ParamStr(1), 1, 6))) <> '-PATH:') then
    begin
      GerarLog('Parâmetro inválido. Use -PATH:<caminho da aplicação>');
      Exit;
    end;

    FPathAplicacao := Trim(Copy(ParamStr(1), 7, Length(ParamStr(1)) - 6));

    if (Trim(FPathAplicacao) = '') then
    begin
      GerarLog('Caminho da aplicação não informado.');
      Exit;
    end;
  {$ENDIF}

  try
     if (FindCmdLineSwitch('DAEMON', ['-'], true)) then
     begin
       TPosixDaemon.Setup(@TratarSinais);

       RunServer;

       if (not FServerIniciado) then
          Halt(TPosixDaemon.EXIT_FAILURE);

       FPidFile:= '';
       if (FindCmdLineSwitch('pidfile', ['-'], true)) then
       begin
         FPidFile:= Trim(ParamStr(5));
         TPosixDaemon.CreatePIDFile(FPidFile);
       end;

       TPosixDaemon.Run(1000, nil);

       StopServer;

       if (Trim(FPidFile) <> '') then
         TPosixDaemon.RemovePIDFile(FPidFile);
     end
     else
     begin
       writeln('Rinha iniciada como aplicação.');
       RunServer;
       writeln('Rinha finalizada!');
     end;
  except
    on E: Exception do
      GerarLog(E.ClassName + ': ' + E.Message, True);
  end;

  // stop program loop
  Terminate;
end;

constructor TRinha.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException:=True;
end;

destructor TRinha.Destroy;
begin
  inherited Destroy;
end;

var
  Application: TRinha;
begin
  Application:=TRinha.Create(nil);
  Application.Title:='Rinha';
  Application.Run;
  Application.Free;
end.

