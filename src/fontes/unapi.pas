unit unAPI;

{$mode ObjFPC}{$H+}

interface

uses
    Classes,
    SysUtils,
    unGenerica,
    unRequisicaoPendente,
    unHealthHelper,
    unPersistencia,
    mormot.core.base,
    mormot.core.variants,
    mormot.core.os,
    mormot.core.json,
    mormot.core.text,
    mormot.core.data,
    mormot.core.threads,
    mormot.orm.core,
    mormot.rest.core,
    mormot.rest.memserver,
    mormot.rest.server,
    mormot.rest.http.server,
    mormot.net.client,
    mormot.net.sock;

type
{ TApiServer }

    TApiServer = class
    private
        FModel: TOrmModel;
        FRest: TRestServerFullMemory;
        FServerHttp: TRestHttpServer;
    public
        constructor Create;
        destructor Destroy; override;

        procedure HandlePayments(Context: TRestServerUriContext);
        procedure HandlePaymentsSummary(Context: TRestServerUriContext);
    end;

{ TWorkerRequisicao }

    TWorkerRequisicao = class(TSynThread)
    private
    protected
        procedure Execute; override;
    public
        constructor Create; reintroduce;
        destructor Destroy; override;
    end;

var
    FilaRequisicoes: TSynQueue;
    Workers: array of TWorkerRequisicao;

implementation

procedure InicializarFilaEPool;
var
    I: Integer;
begin
    FilaRequisicoes:= TSynQueue.Create(TypeInfo(TRequisicaoTempArray));
    SetLength(Workers, FNumMaxWorkers);

    for I := 0 to High(Workers) do
    begin
        Workers[I] := TWorkerRequisicao.Create;
        Workers[I].Start;
    end;
end;

procedure FinalizarFilaEPool;
var
    I: Integer;
begin
    for I := 0 to High(Workers) do
    begin
        Workers[I].Terminate;
        Workers[I].WaitFor;
        Workers[I].Free;
    end;

    FilaRequisicoes.Free;
end;

procedure AdicionarWorkerFila(ACorrelationId: RawUtf8; AAmount: Double; AAttempt: Integer);
var
    lRequisicao: TRequisicaoTemp;
begin
    lRequisicao.CorrelationId := ACorrelationId;
    lRequisicao.Amount := AAmount;
    lRequisicao.Attempt := AAttempt;

    FilaRequisicoes.Push(lRequisicao);
end;

procedure Processar(const AReq : TRequisicaoTemp);
var
    lRequisicao: TRequisicaoPendente;
begin
    lRequisicao:= TRequisicaoPendente.Create(AReq.CorrelationId, AReq.Amount, AReq.Attempt);
    try
        if (lRequisicao.Processar) then
	          Exit;

        if (lRequisicao.attempt > 20) then
        begin
	          GerarLog('Descartado: ' + AReq.CorrelationId, True);
	          Exit;
	      end;

	      ServiceHealthMonitor.VerificarSinal;
	      AdicionarWorkerFila(AReq.CorrelationId, AReq.Amount, lRequisicao.attempt);
    finally
        lRequisicao.Free;
    end;
end;

{ TWorkerRequisicao }

procedure TWorkerRequisicao.Execute;
var
    lRequisicao: TRequisicaoTemp;
begin
    while not Terminated do
    begin
        if (FilaRequisicoes.Count > 0) then
        begin
            if (FilaRequisicoes.Pop(lRequisicao)) then
            begin
                try
                    try
                        Processar(lRequisicao);
                    finally
                    end;
                except
                    on E: Exception do
                        GerarLog('Erro Chamada Processar: ' + E.Message, True);
                end;
            end
            else
                Sleep(FTempoFila);
        end
        else
            Sleep(FTempoFila);
    end;
end;

constructor TWorkerRequisicao.Create;
begin
    inherited Create(False);
end;

destructor TWorkerRequisicao.Destroy;
begin
  inherited Destroy;
end;

{ TApiServer }

procedure TApiServer.HandlePayments(Context: TRestServerUriContext);
var
    lReqJson: TDocVariantData;
    lCorrelationId: RawUtf8;
    lAmount: Double;
    lRetorno: TDocVariantData;
begin
    lReqJson.InitJson(Context.Call^.InBody);

    lReqJson.GetAsRawUtf8('correlationId', lCorrelationId);
    lReqJson.GetAsDouble('amount', lAmount);

    AdicionarWorkerFila(lCorrelationId, lAmount, 0);

    lRetorno.InitJson('', JSON_OPTIONS_FAST);
    Context.ReturnsJson(Variant(lRetorno), HTTP_SUCCESS);
end;

procedure TApiServer.HandlePaymentsSummary(Context: TRestServerUriContext);
var
    lsFrom: RawUtf8;
    lsTo: RawUtf8;
begin
    if (Context.InputExists['from']) then
        lsFrom:= Context.InputUtf8['from']
    else
        lsFrom:= '';

    if (Context.InputExists['to']) then
        lsTo:= Context.InputUtf8['to']
    else
        lsTo:= '';

    Context.ReturnsJson(Variant(Persistencia.ConsultarDados(lsFrom, lsTo)), HTTP_SUCCESS);
end;

constructor TApiServer.Create;
begin
    inherited Create;

    try
        Persistencia:= TPersistencia.Create;
    except
        on E: Exception do
            GerarLog('Criar armazenamento: ' + E.Message);
    end;

    IniciarHealthCk(FUrl);
    InicializarFilaEPool;

    FModel:= TOrmModel.Create([]);

    FRest:= TRestServerFullMemory.Create(FModel);
    FRest.ServiceMethodRegister('payments', @HandlePayments, true);
    FRest.ServiceMethodRegister('payments-summary', @HandlePaymentsSummary, true);;

    FServerHttp:= TRestHttpServer.Create('8080', [FRest], '+', useHttpSocket, FNumMaxWorkersSocket, secNone, '', '', [rsoAllowSingleServerNoRoot, rsoOnlyJsonRequests]);
end;

destructor TApiServer.Destroy;
begin
    FinalizarHealthCk;
    FinalizarFilaEPool;

    FServerHttp.Free;
    FRest.Free;
    FModel.Free;
    FilaRequisicoes.Free;
    Persistencia.Free;
    inherited Destroy;
end;

end.

