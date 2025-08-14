unit unHealthHelper;

{$mode objfpc}{$H+}

interface

uses
    Classes,
    SysUtils,
    DateUtils,
    SyncObjs,
    unGenerica,
    mormot.core.base,
    mormot.core.json,
    mormot.core.variants,
    mormot.net.client,
    mormot.core.os,
    mormot.net.sock;

type

    { TWorkerMonitor }
    TProc = procedure of object;

    TWorkerMonitor = class(TThread)
    private
        FProc: TProc;
    protected
        procedure Execute; override;
    public
        constructor Create(AProc: TProc);
    end;

    TServiceHealthMonitor = class
    private
        FEventoVerificar: TEvent;
        FMonitorLock: TCriticalSection;
        FDefaultAtivo: Integer;
        FUltimaVerificacao: TDateTime;
        FHealthURL: RawUtf8;
        FMonitoramentoAtivo: Boolean;
        FThreadMonitorar: TWorkerMonitor;

        procedure ThreadMonitorar;
        procedure ExecutarHealthCheck;
        procedure Finalizar;
    public
        constructor Create(const AHealthURL: RawUtf8);
        destructor Destroy; override;

        procedure Iniciar;
        procedure VerificarSinal;

        function GetDefaultAtivo: Boolean;
        procedure SetDefaultAtivo(const AValue: Boolean);
    end;

var
    ServiceHealthMonitor: TServiceHealthMonitor;

procedure IniciarHealthCk(const AHealthURL: RawUtf8);
procedure FinalizarHealthCk;

implementation

{ TWorkerMonitor }

procedure TWorkerMonitor.Execute;
begin
    if (Assigned(FProc)) then
        FProc;
end;

constructor TWorkerMonitor.Create(AProc: TProc);
begin
    inherited Create(False);
    FreeOnTerminate:= True;
    FProc:= AProc;
end;

{ TServiceHealthMonitor }

constructor TServiceHealthMonitor.Create(const AHealthURL: RawUtf8);
begin
    FEventoVerificar := TEvent.Create(nil, False, False, '');
    FMonitorLock := TCriticalSection.Create;
    FDefaultAtivo := 1;
    FUltimaVerificacao := IncSecond(Now, -6);
    FHealthURL := AHealthURL;
    FMonitoramentoAtivo := True;
end;

destructor TServiceHealthMonitor.Destroy;
begin
    Finalizar;

    FEventoVerificar.Free;
    FMonitorLock.Free;
    inherited Destroy;
end;

procedure TServiceHealthMonitor.ExecutarHealthCheck;
var
    lClient: THttpClientSocket;
    liStatusCode: Integer;
    lResJson: TDocVariantData;

    lFailing: Boolean;
    lMinResponseTime: Integer;
begin
    lFailing := False;
    lMinResponseTime := 0;

    try
        lClient:= THttpClientSocket.Open(FHealthURL, FPorta, nlTcp, FConTimeOut);
        try
	          lClient.SendTimeout := FReadTimeOut;
            lClient.ReceiveTimeout := FReadTimeOut;

            if (lClient.SockConnected) then
            begin
                liStatusCode:= lClient.Get('/payments/service-health');

                if (liStatusCode = 200) then
                begin
                    lResJson.InitJson(lClient.Content);
                    lResJson.GetAsBoolean('failing', lFailing);
                    lResJson.GetAsInteger('minResponseTime', lMinResponseTime);

                    GerarLog('HealthCheck: Failing=' + lFailing.ToString(True) + ' MinResponseTime=' + IntToStr(lMinResponseTime));
                end
                else
                    GerarLog('HealthCheck: Erro na requisição ' + IntToStr(liStatusCode));
            end
            else
                GerarLog('Erro Conectar Health');
        finally
            lClient.Free;
        end;
    except
        on E: Exception do
            GerarLog('HealthCheck: Erro ' + E.Message);
    end;

    SetDefaultAtivo(not lFailing);
end;

function TServiceHealthMonitor.GetDefaultAtivo: Boolean;
begin
    Result := FDefaultAtivo <> 0;
end;

procedure TServiceHealthMonitor.SetDefaultAtivo(const AValue: Boolean);
begin
    InterlockedExchange(FDefaultAtivo, Ord(AValue));
end;

procedure TServiceHealthMonitor.VerificarSinal;
begin
    FMonitorLock.Enter;
    try
        if SecondsBetween(Now, FUltimaVerificacao) >= 5 then
            FEventoVerificar.SetEvent;
    finally
        FMonitorLock.Leave;
    end;
end;

procedure TServiceHealthMonitor.Iniciar;
begin
    FThreadMonitorar := TWorkerMonitor.Create(@ThreadMonitorar);
end;

procedure TServiceHealthMonitor.Finalizar;
begin
    if not FMonitoramentoAtivo then
        Exit;

    FMonitoramentoAtivo := False;
    FEventoVerificar.SetEvent;

    FThreadMonitorar.WaitFor;
    FThreadMonitorar.Free;
end;

procedure TServiceHealthMonitor.ThreadMonitorar;
begin
    while FMonitoramentoAtivo do
    begin
        if FEventoVerificar.WaitFor(INFINITE) = wrSignaled then
        begin
            if (not FMonitoramentoAtivo) then
                Exit;

            if SecondsBetween(Now, FUltimaVerificacao) >= 5 then
            begin
                FUltimaVerificacao := Now;
                ExecutarHealthCheck;
            end;
        end;
    end;
end;

procedure IniciarHealthCk(const AHealthURL: RawUtf8);
begin
    ServiceHealthMonitor := TServiceHealthMonitor.Create(AHealthURL);
    ServiceHealthMonitor.Iniciar;
end;

procedure FinalizarHealthCk;
begin
    if Assigned(ServiceHealthMonitor) then
        ServiceHealthMonitor.Free;
end;

end.
