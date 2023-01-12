unit uGlobals;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$ModeSwitch implicitfunctionspecialization}

interface

uses
  SysUtils, uArray, uValue;

type

  TGlobalVar = record
    Name: ShortString;
    Value: TValue;
    //class operator Initialize(var GlobalVar: TGlobalVar);
    //class operator Finalize(var GlobalVar: TGlobalVar);
    constructor Create(AName: ShortString; AValue: TValue);
  end;

  TGlobalList = specialize TArrayList<TGlobalVar>;

  PGlobal = ^TGlobal;
  TGlobal = record
    private
      // Global variables and functions
      Globals: TGlobalList;

    public
      function get(const Index: Integer): TGlobalVar;
      procedure put(const Index: Integer; Value: TValue);
      procedure put(const Name: ShortString; Value: TValue);
      function getGlobalIndex(const Name: ShortString): Integer;
      function Exists(const Name: ShortString): Boolean;
      procedure Define(const Name: ShortString);
      procedure addConstant(const Name: ShortString; const Value: Double);
      procedure addNativeFunction(const Name: ShortString; const Arity: Integer;
        Fn: TNativeFn);
  end;

implementation

{ TGlobalVar }

//class operator TGlobalVar.Initialize(var GlobalVar: TGlobalVar);
//begin
//  GlobalVar := Default(TGlobalVar);
//end;
//
//class operator TGlobalVar.Finalize(var GlobalVar: TGlobalVar);
//begin
//  GlobalVar := Default(TGlobalVar);
//end;

constructor TGlobalVar.Create(AName: ShortString; AValue: TValue);
begin
  Name := AName;
  Value := AValue;
end;

{ TGlobal }

function TGlobal.get(const Index: Integer): TGlobalVar;
begin
  Result := Globals[Index];
end;

procedure TGlobal.put(const Index: Integer; Value: TValue);
begin
  if Index >= Globals.Count then
    begin
      Writeln('Global ', Index, ' doesn''t exist.');
      Halt(70);
    end;
  Globals.Data[Index].Value := Value;
end;

procedure TGlobal.put(const Name: ShortString; Value: TValue);
var
  Index: Integer;
begin
  Index := getGlobalIndex(Name);
  Put(Index, Value);
end;

function TGlobal.getGlobalIndex(const Name: ShortString): Integer;
var
  i: Integer;
begin
  if Globals.Count > 0 then
    begin
      for i := Globals.Count - 1 downto 0 do
        if Globals[i].Name = Name then
          Exit(i);
    end;
  Result := -1;
end;

function TGlobal.Exists(const Name: ShortString): Boolean;
begin
  Result := getGlobalIndex(Name) <> -1;
end;

// Register a global
procedure TGlobal.Define(const Name: ShortString);
var
  Index: Integer;
begin
  Index := getGlobalIndex(Name);
  // already defined
  if Index <> -1 then
    Exit;

  // set to default value 0
  Globals.Add(TGlobalVar.Create(Name, NumVal(0)));
end;

procedure TGlobal.addConstant(const Name: ShortString; const Value: Double);
begin
  if not Exists(Name) then
    Globals.Add(TGlobalVar.Create(Name, NumVal(Value)));
end;

procedure TGlobal.addNativeFunction(const Name: ShortString; const Arity: Integer;
  Fn: TNativeFn);
begin
  if not Exists(Name) then
    Globals.Add(TGlobalVar.Create(Name, AllocNative(Fn, Name, Arity)));
end;

end.

