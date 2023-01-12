unit uValue;

{$mode delphi}{$H+}
{$ModeSwitch implicitfunctionspecialization}
{$ModeSwitch functionreferences}
{$ModeSwitch anonymousfunctions}

interface

uses
  SysUtils, Classes, uArray, Generics.Collections;

type
  TValueTyp = (
    vtNumber,
    vtBoolean,
    vtObject
  );

  TObjTyp = (
    otString,
    otCode,
    otNative,
    otFunction,
    otCell
  );

  TObj = class
    Typ: TObjTyp;
    constructor Create(const ATyp: TObjTyp);
  end;

  PValue = ^TValue;
  TValue = record
    case Typ: TValueTyp of
      vtNumber:  (Number: Double);
      vtBoolean: (Bool: Boolean);
      vtObject:  (Obj: TObj);
  end;

  TValues = TArrayList<TValue>;

  TStringObj = class(TObj)
    Data: String;
    constructor Create(const AData: String);
    function toString: String; override;
  end;

  TNativeFn = reference to function(Value: PValue): TValue;

  TNativeObj = class(TObj)
    Func: TNativeFn;
    Name: ShortString;
    Arity: Integer;   // number of parameters / arguments
    constructor Create(aFunction: TNativeFn; aName: ShortString; aArity: Integer);
    function toString: String; override;
  end;

  TCodeObj = class;  // forward declaration

  TCellObj = class(TObj)
    Value: TValue;
    constructor Create(aValue: TValue);
    function toString: String; override;
  end;

  TFunctionObj = class(TObj)
    // Reference to the code object, containing code, locals, etc
    CO: TCodeObj;
    // Captured cells for closures (CodeObject + Cells = Closure)
    Cells: TObjectList<TCellObj>;
    constructor Create(CodeObj: TCodeObj);
    destructor Destroy; override;
    function toString: String; override;
  end;

  TLocalVar = record
    Name: ShortString;
    ScopeLevel: Integer;
    constructor Create(aName: ShortString; aScopeLevel: Integer);
  end;

  TCodeObj = class(TObj)
    // Name of the unit, usually a function name
    Name: String;
    // number of parameters / arguments
    Arity: Integer;
    // Constant pool
    Constants: TValues;
    // Byte code
    Code: TByteArray;
    // current scope level
    ScopeLevel: Integer;
    // Local variables and functions
    Locals: TArrayList<TLocalVar>;
    // Cell variable names
    cellNames: TList<ShortString>;
    // free variable count
    freeCount: Integer;

    constructor Create(const AName: String; const aArity: Integer);
    destructor Destroy; override;
    function toString: String; override;
    procedure addLocal(const AName: ShortString);
    procedure addConst(Value: TValue);
    function getLocalIndex(const AName: ShortString): Integer;
    function getCellIndex(const AName: ShortString): Integer;

  end;

  function asObject(Value: TValue): TObj; inline;
  function isObject(Value: TValue): Boolean; inline;
  function isObjectTyp(Value: TValue; const Typ: TObjTyp): Boolean; inline;
  function ObjVal(Value: TObj): TValue; inline;

  function NumVal(Value: Double): TValue; inline;
  function asNum(Value: TValue): Double; inline;
  function isNum(Value: TValue): Boolean; inline;

  function BoolVal(Value: Boolean): TValue; inline;
  function asBool(Value: TValue): Boolean; inline;
  function isBool(Value: TValue): Boolean; inline;

  function AllocString(const Value: String): TValue;
  function asString(Value: TValue): TStringObj; inline;
  function asPasString(Value: TValue): String; inline;
  function isString(Value: TValue): Boolean; inline;

  function AllocNative(Fn: TNativeFn; const Name: ShortString;
    const Arity: Integer): TValue;
  function asNative(Value: TValue): TNativeObj; inline;
  function isNative(Value: TValue): Boolean; inline;

  function AllocCell(Value: TValue): TValue;
  function asCell(Value: TValue): TCellObj; inline;
  function isCell(Value: TValue): Boolean; inline;
  function CellVal(cellObj: TCellObj): TValue;

  function AllocFunction(CodeObj: TCodeObj): TValue;
  function asFunction(Value: TValue): TFunctionObj; inline;
  function isFunction(Value: TValue): Boolean; inline;

  function AllocCode(const Name: String; const Arity: Integer): TValue;
  function asCode(Value: TValue): TCodeObj; inline;
  function isCode(Value: TValue): Boolean; inline;

  function ValueToString(Value: TValue): String;
  function ValueToTypeString(Value: TValue): String;

implementation

function asObject(Value: TValue): TObj; inline;
begin
  Result := Value.Obj;
end;

function isObject(Value: TValue): Boolean; inline;
begin
  Result := Value.Typ = vtObject;
end;

function isObjectTyp(Value: TValue; const Typ: TObjTyp): Boolean;
begin
  Result := isObject(Value) and (asObject(Value).Typ = Typ);
end;

function ObjVal(Value: TObj): TValue;
begin
  Result.Typ := vtObject;
  Result.Obj := Value;
end;

function NumVal(Value: Double): TValue; inline;
begin
  Result.Typ := vtNumber;
  Result.Number := Value;
end;

function asNum(Value: TValue): Double;
begin
  Result := Value.Number;
end;

function isNum(Value: TValue): Boolean;
begin
  Result := Value.Typ = vtNumber;
end;

function BoolVal(Value: Boolean): TValue;
begin
  Result.Typ := vtBoolean;
  Result.Bool := Value;
end;

function asBool(Value: TValue): Boolean;
begin
  Result := Value.Bool;
end;

function isBool(Value: TValue): Boolean;
begin
  Result := Value.Typ = vtBoolean;
end;

function AllocString(const Value: String): TValue;
begin
  Result.Typ := vtObject;
  Result.Obj := TObj(TStringObj.Create(Value));
end;

function asString(Value: TValue): TStringObj;
begin
  Result := TStringObj(Value.Obj);
end;

function asPasString(Value: TValue): String;
begin
  Result := AsString(Value).Data;
end;

function isString(Value: TValue): Boolean;
begin
  Result := isObjectTyp(Value, otString);
end;

function AllocNative(Fn: TNativeFn; const Name: ShortString;
  const Arity: Integer): TValue;
begin
  Result.Typ := vtObject;
  Result.Obj := TObj(TNativeObj.Create(Fn, Name, Arity));
end;

function asNative(Value: TValue): TNativeObj;
begin
  Result := TNativeObj(Value.Obj);
end;

function isNative(Value: TValue): Boolean;
begin
  Result := isObjectTyp(Value, otNative);
end;

function AllocCell(Value: TValue): TValue;
begin
  Result.Typ := vtObject;
  Result.Obj := TObj(TCellObj.Create(Value));
end;

function asCell(Value: TValue): TCellObj;
begin
  Result := TCellObj(Value.Obj);
end;

function isCell(Value: TValue): Boolean;
begin
  Result := isObjectTyp(Value, otCell);
end;

function CellVal(cellObj: TCellObj): TValue;
begin
  Result := ObjVal(TObj(cellObj));
end;

function AllocFunction(CodeObj: TCodeObj): TValue;
begin
  Result.Typ := vtObject;
  Result.Obj := TObj(TFunctionObj.Create(CodeObj));
end;

function asFunction(Value: TValue): TFunctionObj;
begin
  Result := TFunctionObj(Value.Obj);
end;

function isFunction(Value: TValue): Boolean;
begin
  Result := isObjectTyp(Value, otFunction);
end;

function AllocCode(const Name: String; const Arity: Integer): TValue;
begin
  Result.Typ := vtObject;
  Result.Obj := TObj(TCodeObj.Create(Name, Arity));
end;

function asCode(Value: TValue): TCodeObj;
begin
  Result := TCodeObj(Value.Obj);
end;

function isCode(Value: TValue): Boolean;
begin
  Result := isObjectTyp(Value, otCode);
end;

function ValueToString(Value: TValue): String;
begin
  case Value.Typ of
    vtNumber: Result := Value.Number.ToString;
    vtBoolean: Result := IfThen(Value.Bool, 'true', 'false');
    vtObject: Result := Value.Obj.ToString;
  end;
end;

function ValueToTypeString(Value: TValue): String;
begin
  if isNum(Value) then Result := 'NUMBER'
  else if isBool(Value) then Result := 'BOOLEAN'
  else if isString(Value) then Result := 'STRING'
  else if isCode(Value) then Result := 'CODE'
  else if isNative(Value) then Result := 'NATIVE'
  else if isCell(Value) then Result := 'CELL'
  else if isFunction(Value) then Result := 'FUNCTION'
  else WriteStr(Result, 'UNKNOWN TYPE: ', Value.Typ);
end;

{ TObj }

constructor TObj.Create(const ATyp: TObjTyp);
begin
  Typ := ATyp;
end;

{ TStringObj }

constructor TStringObj.Create(const AData: String);
begin
  inherited Create(otString);
  Data := AData;
end;

function TStringObj.toString: String;
begin
  Result := '"' + Data + '"';
end;

{ TNativeObj }

constructor TNativeObj.Create(aFunction: TNativeFn; aName: ShortString;
  aArity: Integer);
begin
  inherited Create(otNative);
  Func := aFunction;
  Name := aName;
  Arity := aArity;
end;

function TNativeObj.toString: String;
begin
  Result := Name + '/' + IntToStr(Arity);
end;

{ TCellObj }

constructor TCellObj.Create(aValue: TValue);
begin
  inherited Create(otCell);
  Value := aValue;
end;

function TCellObj.toString: String;
begin
  Result := ValueToString(Value);
end;

{ TFunctionObj }

constructor TFunctionObj.Create(CodeObj: TCodeObj);
begin
  inherited Create(otFunction);
  CO := CodeObj;
  // a closure doesn't own the cell objects, only the list, therefore Create(False).
  Cells := TObjectList<TCellObj>.Create(False);
end;

destructor TFunctionObj.Destroy;
begin
  Cells.Free;
  if Assigned(CO) then CO.Free;
  inherited Destroy;
end;

function TFunctionObj.toString: String;
begin
  Result := CO.Name + '/' + IntToStr(CO.Arity);
end;

{ TLocalVar }

constructor TLocalVar.Create(AName: ShortString; AScopeLevel: Integer);
begin
  Name := AName;
  ScopeLevel := AScopeLevel;
end;

{ TCodeObj }

constructor TCodeObj.Create(const AName: String; const aArity: Integer);
begin
  inherited Create(otCode);
  Name := aName;
  Arity := aArity;
  scopeLevel := 0;
  freeCount := 0;
  cellNames := TList<ShortString>.create;
end;

destructor TCodeObj.Destroy;
begin
  cellNames.Free;
  inherited Destroy;
end;


function TCodeObj.toString: String;
begin
  Result := '<Code ' + Name + '>';
end;

procedure TCodeObj.addLocal(const AName: ShortString);
begin
  Locals.Add(TLocalVar.Create(AName, scopeLevel));
end;

procedure TCodeObj.addConst(Value: TValue);
begin
  Constants.Add(Value);
end;

function TCodeObj.getLocalIndex(const AName: ShortString): Integer;
var
  i: Integer;
begin
  if Locals.Count > 0 then
    for i := Locals.Count - 1 downto 0 do
      if Locals[i].Name = AName then
        Exit(i);

  Result := -1;
end;


// cellNames contains free variables + own cells
function TCodeObj.getCellIndex(const AName: ShortString): Integer;
var
  i: Integer;
begin
  if cellNames.Count > 0 then
    for i := cellNames.Count - 1 downto 0 do
      if cellNames[i] = AName then
        Exit(i);

  Result := -1;
end;


end.

