unit unRequisicaoPendente;

{$mode ObjFPC}{$H+}

interface

uses
    Classes,
    SysUtils,
    DateUtils,
    unGenerica,
    unHealthHelper,
    unPersistencia,
    mormot.core.base,
    mormot.core.variants,
    mormot.core.os,
    mormot.core.json,
    mormot.core.text,
    mormot.core.data,
    mormot.orm.core,
    mormot.rest.core,
    mormot.rest.memserver,
    mormot.rest.server,
    mormot.net.client,
    mormot.core.datetime,
    mormot.net.sock;

type

    { TRequisicaoPendente }

    TRequisicaoPendente = class
    private
        FCorrelationId: RawUtf8;
        FAmount: Double;
        FAttempt: Integer;
	      FRequestedAt: RawUtf8;
        FJsonObj: TDocVariantData;

	      procedure AjustarDataHora;
    public
        constructor Create(const AId: RawUtf8; AAmount: Double; AAttempt: Integer);
        destructor Destroy; override;

	      function Processar: Boolean;

        property CorrelationId: RawUtf8 read FCorrelationId;
        property Amount: Double read FAmount;
        property Attempt: Integer read FAttempt write FAttempt;
    end;

    TRequisicaoTemp = record
        CorrelationId: RawUtf8;
        Amount: Double;
        Attempt: Integer;
    end;

    TRequisicaoTempArray = array of TRequisicaoTemp;

implementation

{ TRequisicaoPendente }

constructor TRequisicaoPendente.Create(const AId: RawUtf8; AAmount: Double; AAttempt: Integer);
begin
    FCorrelationId:= AId;
    FAmount:= AAmount;
    FAttempt:= AAttempt;

    FJsonObj.InitFast;
    FJsonObj.AddValue('correlationId', FCorrelationId);
    FJsonObj.AddValue('amount', FAmount);
end;

destructor TRequisicaoPendente.Destroy;
begin
    inherited Destroy;
end;

procedure TRequisicaoPendente.AjustarDataHora;
begin
    //GetUniqueTimestamp;
    FRequestedAt:= DateTimeToIso8601Text(LocalTimeToUniversal(Now));

    FJsonObj.AddOrUpdateValue('requestedAt', FRequestedAt);
end;

function TRequisicaoPendente.Processar: Boolean;
var
    lbDefault: Boolean;
    lsURL: RawUtf8;
    lClient: THttpClientSocket;
    liStatusCode: Integer;
begin
    try
        lbDefault:= True;
        if (FAttempt > FNumTentativasDefault) then
            lbDefault:= ServiceHealthMonitor.GetDefaultAtivo;

        if lbDefault then
            lsURL:= FUrl
        else
            lsURL:= FUrlFall;

        lClient:= THttpClientSocket.Open(lsURL, FPorta, nlTcp, FConTimeOut);
        try
            lClient.SendTimeout:= FReadTimeOut;
            lClient.ReceiveTimeout:= FReadTimeOut;

            if (lClient.SockConnected) then
            begin
                AjustarDataHora;
                liStatusCode:= lClient.Post('/payments', FJsonObj.ToJson, 'application/json');

                if (liStatusCode = 200) then
                begin
                    if (lbDefault) then
                        FJsonObj.AddOrUpdateValue('service', 0)
                    else
                        FJsonObj.AddOrUpdateValue('service', 1);

                    Persistencia.AdicionarRegistro(FromVariant(FJsonObj));

                    if (FAttempt <= FNumTentativasDefault) and (not ServiceHealthMonitor.GetDefaultAtivo) then
                        ServiceHealthMonitor.SetDefaultAtivo(True);

                    Result := True;
                    Exit;
                end;
            end;
        finally
            lClient.Free;
        end;
    except
    on E: Exception do
        GerarLog('Erro Processar: ' + E.Message, True);
    end;

    Inc(FAttempt);
    Result := False;
end;

end.


