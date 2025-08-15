unit unGenerica;

{$mode ObjFPC}{$H+}

interface

uses
    SysUtils,
    SyncObjs,
    DateUtils,
    mormot.core.base;

type
    TUrlParts = record
        Protocol: RawUtf8;
        Host: RawUtf8;
        Port: RawUtf8;
        Uri: RawUtf8;
    end;

function GetUniqueTimestamp: TDateTime;
function DateTimeToUnixMS(const ADateTime: TDateTime): Int64;
procedure CarregarVariaveisAmbiente;
function GetEnv(const lsEnvVar, lsDefault: string): string;
procedure GerarLog(lsMsg: String; lbForca: Boolean = False);

var
    FPathAplicacao: String;
    FServerIniciado: Boolean;
    FPidFile: String;
    FLogLock: TCriticalSection;
    FDebug: Boolean;
    FUrl: String;
    FPorta: String;
    FUrlFall: String;
    FPortaFall: String;
    FUrlConsolida: String;
    FPortaConsolida: String;
    FConTimeOut: Integer;
    FReadTimeOut: Integer;
    FNumMaxWorkers: Integer;
    FNumMaxWorkersSocket: Integer;
    FTempoFila: Integer;
    FNumTentativasDefault: Integer;
    FLastTimestamp: Int64;
    FTimestampLock: TCriticalSection;
    FHttpLock: TCriticalSection;

const
    cTransacaoPath = '/opt/rinha/transacoes/';

implementation

function DateTimeToUnixMS(const ADateTime: TDateTime): Int64;
begin
    Result := Round((ADateTime - UnixDateDelta) * MSecsPerDay);
end;

function UnixMSToDateTime(const MS: Int64): TDateTime;
begin
    Result := (MS / MSecsPerDay) + UnixDateDelta;
end;

function GetUniqueTimestamp: TDateTime;
var
    lCurrent: Int64;
begin
    FTimestampLock.Enter;
    try
        lCurrent := DateTimeToUnixMS(Now);
        if lCurrent <= FLastTimestamp then
            lCurrent := FLastTimestamp + 1;
        FLastTimestamp := lCurrent;
        Result := UnixMSToDateTime(lCurrent);
    finally
        FTimestampLock.Leave;
    end;
end;

procedure ParseUrl(const AUrl: RawUtf8; out Protocol, Host, Port, URI: RawUtf8);
var
    p, p2: Integer;
begin
    Protocol := '';
    Host := '';
    Port := '';
    URI := '';

    // Detecta protocolo
    p := Pos('://', AUrl);
    if p > 0 then
    begin
        Protocol := Copy(AUrl, 1, p - 1);
        p := p + 3;
    end
    else
        p := 1;

    // Detecta URI
    p2 := PosEx('/', AUrl, p);
    if p2 > 0 then
    begin
        Host := Copy(AUrl, p, p2 - p);
        URI := Copy(AUrl, p2, Length(AUrl));
    end
    else
        Host := Copy(AUrl, p, Length(AUrl));

    // Detecta porta (se houver)
    p := Pos(':', Host);
    if p > 0 then
    begin
        Port := Copy(Host, p + 1, Length(Host));
        Host := Copy(Host, 1, p - 1);
    end
    else
    begin
        // Porta padrão dependendo do protocolo
        if Protocol = 'https' then
            Port := '443'
        else
            Port := '80';
    end;
end;

function ExtrairHostPortaUri(const AUrl: String): TUrlParts;
var
    lUrlUtl8: RawUtf8;
begin
    lUrlUtl8:= UTF8Encode(AUrl);
    ParseUrl(lUrlUtl8, Result.Protocol, Result.Host, Result.Port, Result.Uri);
end;

function GetEnv(const lsEnvVar, lsDefault: string): string;
begin
    Result := GetEnvironmentVariable(lsEnvVar);
    if Result = '' then
        Result := lsDefault;
end;

procedure AppendStrToFile(const AFileName, ATextToAppend: string);
var
    lF: TextFile;
begin
    AssignFile(lF, AFileName);

    try
        if FileExists(AFileName) then
            Append(lF)
        else
            Rewrite(lF);

        Writeln(lF, ATextToAppend);
    finally
        CloseFile(lF);
    end;
end;

procedure GerarLog(lsMsg: String; lbForca: Boolean);
var
    lsArquivo: String;
    lsData: String;
begin
    {$IFNDEF DEBUG}
    if (not FDebug) and (not lbForca) then
        Exit;
    {$ENDIF}

    {$IFNDEF SERVICO}
    WriteLn(lsMsg);
    {$ENDIF}

    FLogLock.Enter;
    try
        try
            if Trim(FPathAplicacao) = '' then
                FPathAplicacao := '/opt/rinha/';

            lsData := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', Now);
            lsArquivo := FPathAplicacao + 'Logs' + PathDelim + 'log' + FormatDateTime('ddmmyyyy', Date) + '.txt';
            AppendStrToFile(lsArquivo, lsData + ':' + lsMsg);
        except
        end;
    finally
        FLogLock.Leave;
    end;
end;

procedure CarregarVariaveisAmbiente;
var
    lURL: TUrlParts;
begin
    FDebug := GetEnv('DEBUG', 'N') = 'S';

    lURL := ExtrairHostPortaUri(GetEnv('DEFAULT_URL', 'http://localhost:8001'));
    FUrl := lURL.Host;
    FPorta := lURL.Port;

    lURL := ExtrairHostPortaUri(GetEnv('FALLBACK_URL', 'http://localhost:8002'));
    FUrlFall := lURL.Host;
    FPortaFall := lURL.Port;

    lURL := ExtrairHostPortaUri(GetEnv('CONSOLIDA_URL', 'http://localhost:9090'));
    FUrlConsolida := lURL.Host;
    FPortaConsolida := lURL.Port;

    FConTimeOut := StrToIntDef(GetEnv('CON_TIME_OUT', ''), 3000);
    FReadTimeOut := StrToIntDef(GetEnv('READ_TIME_OUT', ''), 3000);
    FNumMaxWorkers := StrToIntDef(GetEnv('NUM_WORKERS', ''), 0);
    FNumMaxWorkersSocket := StrToIntDef(GetEnv('NUM_WORKERS_SOCKET', ''), 32);
    FTempoFila := StrToIntDef(GetEnv('TEMPO_FILA', ''), 500);
    FNumTentativasDefault := StrToIntDef(GetEnv('NUM_TENTATIVAS_DEFAULT', ''), 5);

    if FConTimeOut < 0 then
        FConTimeOut := 3000;

    if FReadTimeOut < 0 then
        FReadTimeOut := 3000;

    if FNumMaxWorkers < 0 then
        FNumMaxWorkers := 1;

    if FNumMaxWorkersSocket < 0 then
        FNumMaxWorkersSocket := 1;

    if FTempoFila < 0 then
        FTempoFila := 500;

    if FNumTentativasDefault < 0 then
        FNumTentativasDefault := 1;
end;

initialization
    FLogLock := TCriticalSection.Create;
    FTimestampLock := TCriticalSection.Create;
    FLastTimestamp := DateTimeToUnixMS(Now);
    FHttpLock := TCriticalSection.Create;

finalization
    FLogLock.Free;
    FTimestampLock.Free;
    FHttpLock.Free;

end.

