unit unPersistencia;

{$mode objfpc}{$H+}

interface

uses
    Classes, 
    SysUtils, 
    DateUtils,
    BaseUnix, 
    Unix, 
    ctypes,
    Generics.Collections,
    mormot.core.base,
    mormot.core.variants,
    mormot.core.json;

type
    Psem_t = Pointer;

    generic TArray<T> = array of T;

    TRegistro = packed record
        CorrelationId: array[0..35] of AnsiChar;
        Amount: Double;
        RequestedAt: array[0..23] of AnsiChar;
        Service: Integer;
    end;

    TRegistroArray = specialize TArray<TRegistro>;

    type
        PRegistro = ^TRegistro;

    TPersistencia = class
    private
        FPtr: Pointer;
        FFD: cint;
        FSem: Psem_t;
    public
        constructor Create;
        destructor Destroy; override;
        procedure AdicionarRegistro(const AReg: TRegistro);
        function LerTodos: TRegistroArray;
        function ConsultarDados(const AFrom, ATo: string): TDocVariantData;

        class procedure LimparMemoriaCompartilhada;
    end;

function sem_open(name: PChar; oflag: cint; mode: mode_t; value: cuint): Pointer; cdecl; external 'c';
function sem_close(sem: Pointer): cint; cdecl; external 'c';
function sem_post(sem: Pointer): cint; cdecl; external 'c';
function sem_wait(sem: Pointer): cint; cdecl; external 'c';
function sem_unlink(name: PChar): cint; cdecl; external 'c';
function ftruncate(fd: cint; length: Int64): cint; cdecl; external 'c';
function mmap(addr: Pointer; length: size_t; prot, flags: cint; fd: cint; offset: Int64): Pointer; cdecl; external 'c';
function munmap(addr: Pointer; length: size_t): cint; cdecl; external 'c';

function FromVariant(const AVariant: TDocVariantData): TRegistro;

const
    SHM_PATH = '/dev/shm/bloco_memoria';
    SHM_SIZE = 20 * 1024 * 1024; // 20 MB
    REG_SIZE = SizeOf(TRegistro);
    MAX_REGISTROS = SHM_SIZE div REG_SIZE;
    SEM_FAILED: Pointer = Pointer(-1);

var
    Persistencia: TPersistencia;

implementation

function CriarSemaforo: Psem_t;
begin
    Result := sem_open('/semaforo_memoria', O_CREAT, &666, 1);
    if Result = SEM_FAILED then
        raise Exception.Create('Erro ao criar semáforo');
end;

function FromVariant(const AVariant: TDocVariantData): TRegistro;
begin
    FillChar(Result, SizeOf(Result), 0);

    StrPLCopy(Result.CorrelationId, AVariant.Value['correlationId'], Length(Result.CorrelationId));
    Result.Amount := AVariant.Value['amount'];
    StrPLCopy(Result.RequestedAt, AVariant.Value['requestedAt'], Length(Result.RequestedAt));
    Result.Service := AVariant.Value['service'];
end;

{ TPersistencia }

class procedure TPersistencia.LimparMemoriaCompartilhada;
begin
    try
        if FileExists(SHM_PATH) then
        begin
            DeleteFile(SHM_PATH);
            WriteLn('Memória compartilhada removida.');
        end;
    except
        on E: Exception do
            WriteLn('Erro ao remover memória: ', E.Message);
    end;

    try
        sem_unlink('/semaforo_memoria');
        WriteLn('Semáforo removido.');
    except
        on E: Exception do
            WriteLn('Erro ao remover semáforo: ', E.Message);
    end;
end;

procedure TPersistencia.AdicionarRegistro(const AReg: TRegistro);
var
    I: Integer;
    lPReg: ^TRegistro;
    lbAdicionado: Boolean;
begin
    lbAdicionado := False;
    sem_wait(FSem);
    try
        for I := 0 to MAX_REGISTROS - 1 do
        begin
            lPReg := Pointer(PtrUInt(FPtr) + PtrUInt(I * REG_SIZE));
            if lPReg^.CorrelationId[0] = #0 then
            begin
                lPReg^ := AReg;
                lbAdicionado := True;
                Break;
            end;
        end;
    finally
        sem_post(FSem);
    end;

    if not lbAdicionado then
        raise Exception.Create('Memória cheia: não foi possível adicionar o registro');
end;

constructor TPersistencia.Create;
begin
    FFD := fpOpen(SHM_PATH, O_CREAT or O_RDWR, &666);
    if FFD = -1 then
        raise Exception.Create('Erro ao abrir memória');

    if ftruncate(FFD, SHM_SIZE) = -1 then
        raise Exception.Create('Erro ao definir tamanho');

    FPtr := mmap(nil, SHM_SIZE, PROT_READ or PROT_WRITE, MAP_SHARED, FFD, 0);
    if FPtr = MAP_FAILED then
        raise Exception.Create('Erro ao mapear memória');

    FSem := CriarSemaforo;
end;

destructor TPersistencia.Destroy;
begin
    munmap(FPtr, SHM_SIZE);
    fpClose(FFD);
    sem_close(FSem);
    inherited;
end;

function TPersistencia.LerTodos: TRegistroArray;
var
    I: Integer;
    lPReg: ^TRegistro;
    lLista: specialize TList<TRegistro>;
begin
    lLista := specialize TList<TRegistro>.Create;
    try
        sem_wait(FSem);
        for I := 0 to MAX_REGISTROS - 1 do
        begin
            lPReg := PRegistro(PtrUInt(FPtr) + PtrUInt(I * REG_SIZE));
            if lPReg^.CorrelationId[0] <> #0 then
                lLista.Add(lPReg^);
        end;
        sem_post(FSem);
        Result := lLista.ToArray;
    finally
      lLista.Free;
    end;
end;

function TPersistencia.ConsultarDados(const AFrom, ATo: string): TDocVariantData;
var
    lReg: TRegistro;
    ldReg: TDateTime;
    ldFrom: TDateTime;
    ldTo: TDateTime;
    lbFrom: Boolean;
    lbTo: Boolean;
    TotalDefault: Integer;
    TotalFallback: Integer;
    AmountDefault: Double;
    AmountFallback: Double;
    lDefault: TDocVariantData; 
    lFallback: TDocVariantData; 
    lResultado: TDocVariantData;
    lTodos: specialize TArray<TRegistro>;
begin
    TotalDefault := 0;
    TotalFallback := 0;
    AmountDefault := 0;
    AmountFallback := 0;

    lbFrom := (Trim(AFrom) <> '') and TryISO8601ToDate(AFrom, ldFrom, True);
    lbTo := (Trim(ATo) <> '') and TryISO8601ToDate(ATo, ldTo, True);

    lTodos := LerTodos;

    for lReg in lTodos do
    begin
        if not TryISO8601ToDate(string(lReg.RequestedAt), ldReg, True) then
            Continue;

         if (not lbFrom or (ldReg >= ldFrom)) and
            (not lbTo or (ldReg <= ldTo)) then
        begin
            if lReg.Service = 0 then
            begin
                Inc(TotalDefault);
                AmountDefault := AmountDefault + lReg.Amount;
            end
            else
            begin
                Inc(TotalFallback);
                AmountFallback := AmountFallback + lReg.Amount;
            end;
        end;
    end;

    lDefault.InitFast;
    lDefault.AddValue('totalRequests', TotalDefault);
    lDefault.AddValue('totalAmount', AmountDefault);

    lFallback.InitFast;
    lFallback.AddValue('totalRequests', TotalFallback);
    lFallback.AddValue('totalAmount', AmountFallback);

    lResultado.InitFast;
    lResultado.AddValue('default', Variant(lDefault));
    lResultado.AddValue('fallback', Variant(lFallback));

    Result := lResultado;
end;

end.
