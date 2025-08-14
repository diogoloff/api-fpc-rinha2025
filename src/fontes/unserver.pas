unit unServer;

{$mode ObjFPC}{$H+}

interface

uses
    Classes,
    SysUtils,
    unGenerica,
    unAPI;

procedure RunServer;
procedure StopServer;

var
    FServerHttp: TApiServer;

implementation

procedure StartServer;
begin
    GerarLog('Iniciado');

    CarregarVariaveisAmbiente;

    GerarLog('Configuração do Ambiente');
    GerarLog('==================================');
    GerarLog('(DEBUG) Debug Ativo: ' + BoolToStr(FDebug, True));
    GerarLog('(DEFAULT_URL) Url Default: ' + FUrl);
    GerarLog('(FALLBACK_URL) Url Fallback: ' + FUrlFall);
    GerarLog('(CON_TIME_OUT) Timeout Conexão: ' + IntToStr(FConTimeOut));
    GerarLog('(READ_TIME_OUT) Timeout Retorno: ' + IntToStr(FReadTimeOut));
    GerarLog('(NUM_WORKERS) Quantidade de Workers na Fila: ' + IntToStr(FNumMaxWorkers));
    GerarLog('(NUM_WORKERS_SOCKET) Quantidade de Workers no Socket: ' + IntToStr(FNumMaxWorkersSocket));
    GerarLog('(TEMPO_FILA) Tempo Descarga de Fila: ' + IntToStr(FTempoFila));
    GerarLog('(NUM_TENTATIVAS_DEFAULT) Numero de Tentativas Default: ' + IntToStr(FNumTentativasDefault));

    FServerHttp:= TApiServer.Create;
end;

procedure StopServer;
begin
    GerarLog('Parado');
    FServerHttp.Free;
    FServerIniciado:= False;
end;

procedure ListarComandos;
begin
    Writeln('Comandos disponiveis');
    Writeln('start: Iniciar server');
    Writeln('stop: Parar server');
    Writeln('help: Ajuda');
    Writeln('exit: Sair da aplicação');
end;

procedure RunServer;
    procedure ModoConsole;
    var
        lsResposta: String;
    begin
        ListarComandos;
        while True do
        begin
            Readln(lsResposta);
            lsResposta:= LowerCase(lsResposta);
            if (SameText(lsResposta, 'start')) then
                StartServer
            else if (SameText(lsResposta, 'stop')) then
                StopServer
            else if (SameText(lsResposta, 'help')) then
                ListarComandos
            else if (SameText(lsResposta, 'exit')) then
            begin
                StopServer;
                Break;
            end
            else
                Writeln('Comando inválido');
        end;
    end;
begin
    FServerIniciado:= True;

    {$IFDEF SERVICO}
    StartServer;
    {$ELSE}
    FPathAplicacao := '/home/publico/Diogo/Rinha/';
    ModoConsole;
    {$ENDIF}
end;

end.

