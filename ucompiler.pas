unit uCompiler;

{$mode delphi}{$H+}
{$ModeSwitch implicitfunctionspecialization}

interface

uses
  SysUtils, uAST, uValue, Generics.Collections, uDisassembler, uGlobals, uScope;

type

  // List of all code objects
  TCodeObjects = TObjectList<TCodeObj>;

  TCompiler = record
    private
      CO: TCodeObj;
      Main: TFunctionObj;         // main entry point (function)
      ScopeInfo_: TDictionary<TExpr, PScope>;
      ScopeStack_: TStack<PScope>; // stack of scopes
      CodeObjects: TCodeObjects;  // all code objects
      Global: PGlobal;
      class operator Initialize(var Compiler: TCompiler);
      class operator Finalize(var Compiler: TCompiler);
    public
      property getMainFunction: TFunctionObj read Main; // retruns main function: entry point
      procedure Init(AGlobal: PGlobal);
      procedure Compile(Expr: TExpr);
      procedure Gen(Expr: TExpr);
      procedure DisassembleBytecode;
    private
      CompareOps: TDictionary<String, Byte>; // map of strings and compare operators
      Disassembler: TDisassembler;
      procedure Emit(Code: Byte);
      function NumericConstIdx(const Value: Double): Integer;
      function StringConstIdx(const Value: String): Integer;
      function BooleanConstIdx(const Value: Boolean): Integer;
      procedure GenBinaryOp(const Op: Byte; Expr1, Expr2: TExpr);
      function getOffSet: Integer;
      procedure writeByteAtOffSet(OffSet: Integer; Value: Byte);
      procedure patchJumpAddress(OffSet: Integer; Value: UInt16);
      procedure BlockEnter;
      procedure BlockExit;
      function CreateCodeObjectValue(const Name: ShortString;
        const Arity: Integer = 0): TValue;
      function isGlobalScope: Boolean;
      function isFunctionBody: Boolean;
      function isDeclaration(Expr: TExpr): Boolean;
      function isVarDeclaration(Expr: TExpr): Boolean;
      function isDefDeclaration(Expr: TExpr): Boolean;
      function isLambda(Expr: TExpr): Boolean;
      function isBlock(Expr: TExpr): Boolean;
      function isTaggedList(Expr: TExpr; const Tag: ShortString): Boolean;
      function getVarsCountOnScopeExit: Integer;
      procedure compileFunction(Expr: TExpr; const fnName: ShortString;
        Params: TExpr; Body: TExpr);
      procedure Analyze(Expr: TExpr; Scope: PScope);
  end;

implementation
uses uOpcodes{, uLogger};

{ TCompiler }

class operator TCompiler.Initialize(var Compiler: TCompiler);
begin
  // Map of compare operators
  Compiler.CompareOps := TDictionary<String, Byte>.Create;
  Compiler.CompareOps.Add('<', 0);
  Compiler.CompareOps.Add('>', 1);
  Compiler.CompareOps.Add('=', 2);
  Compiler.CompareOps.Add('>=', 3);
  Compiler.CompareOps.Add('<=', 4);
  Compiler.CompareOps.Add('<>', 5);

  Compiler.ScopeInfo_ := TDictionary<TExpr, PScope>.Create;
  Compiler.ScopeStack_ := TStack<PScope>.create();
  Compiler.CodeObjects := TCodeObjects.Create();
end;

class operator TCompiler.Finalize(var Compiler: TCompiler);
begin
  Compiler.ScopeInfo_.Free;
  Compiler.ScopeStack_.Free;
  Compiler.CompareOps.Free;
  Compiler.CO.Free;
end;

procedure TCompiler.Init(AGlobal: PGlobal);
begin
  Global := AGlobal;
end;

procedure TCompiler.Compile(Expr: TExpr);
begin
  CO := asCode(createCodeObjectValue('main'));
  Main := asFunction(AllocFunction(CO));

  // Scope analysis
  Analyze(Expr, Nil);

  // Generate recursively from top-level
  Gen(Expr);

  // Explicitly VM-stop marker
  Emit(OP_HALT);
end;

// Main compile loop
procedure TCompiler.Gen(Expr: TExpr);
var
  Tag: TExpr;
  Op, VarName, fnName: String;
  elseJmpAddr, elseBranchAddr, endAddr, endBranchAddr, GlobalIndex, i,
    loopStartAddr, loopEndJmpAddr, loopEndAddr: Integer;
  isLast, isDecl: Boolean;
  opCodeGetter, opCodeSetter: Byte;
begin
  //writeln('TCompiler.Gen expr type = ', Expr.Typ, '  symbol = ', Expr.Str);
  case Expr.Typ of
    etNumber:
      begin
        Emit(OP_CONST);
        Emit(NumericConstIdx(Expr.Num));
      end;
    etString:
      begin
        Emit(OP_CONST);
        Emit(StringConstIdx(Expr.Str));
      end;
    etSymbol:  // variables, operators
      begin
        // Booleans
        if (Expr.Str = 'true') or (Expr.Str = 'false') then
          begin
            Emit(OP_CONST);
            Emit(BooleanConstIdx(IfThen(Expr.Str = 'true', True, False)));
          end
        else // variables:
          begin
            VarName := Expr.Str;
            opCodeGetter := ScopeStack_.Peek^.getNameGetter(VarName);
            Emit(opCodeGetter);

            // 1. Local vars
            if opCodeGetter = OP_GET_LOCAL then
              Emit(CO.getLocalIndex(VarName))

            else if opCodeGetter = OP_GET_CELL then
              Emit(CO.getCellIndex(VarName))

            else
              begin
                // 2. Global variables
                if not Global^.Exists(VarName) then
                  begin
                    Writeln('[Compiler]: Reference error: ', VarName);
                    Halt;
                  end;
                Emit(Global^.getGlobalIndex(VarName));
              end;
          end
      end;
    etList:
      begin
        Tag := Expr.List[0];
        if Tag.Typ = etSymbol then
          begin
            Op := Tag.Str;
            // Binary operations
            if Op = '+' then
              GenBinaryOp(OP_ADD, Expr.List[1], Expr.List[2])
            else if Op = '-' then
              GenBinaryOp(OP_SUB, Expr.List[1], Expr.List[2])
            else if Op = '*' then
              GenBinaryOp(OP_MUL, Expr.List[1], Expr.List[2])
            else if Op = '/' then
              GenBinaryOp(OP_DIV, Expr.List[1], Expr.List[2])
            // Compare operations
            else if CompareOps.ContainsKey(Op) then
              begin
                Gen(Expr.List[1]);
                Gen(Expr.List[2]);
                Emit(OP_COMPARE);
                Emit(CompareOps[Op]);
              end
            // if expr: (if <test> <consequent> <alternate>
            else if Op = 'if' then
              begin
                Gen(Expr.List[1]); // test condition
                Emit(OP_JUMP_IF_FALSE);

                // Else branch. Init with 0 address, will be patched, 2 bytes
                Emit(0);
                Emit(0);
                elseJmpAddr := getOffset - 2;

                Gen(Expr.List[2]); // consequent part
                Emit(OP_JUMP);
                // place holder
                Emit(0);
                Emit(0);
                endAddr := getOffset - 2;

                elseBranchAddr := getOffset;
                patchJumpAddress(elseJmpAddr, elseBranchAddr);

                // alternate part if we have it
                if Expr.List.Count = 4 then
                  Gen(Expr.List[3]);

                endBranchAddr := getOffSet;
                patchJumpAddress(endAddr, endBranchAddr);
              end
            else if Op = 'while' then   // (while <test> <body>)
              begin
                loopStartAddr := getOffSet;
                Gen(Expr.List[1]); // test condition
                // loop end, Init with 0 address, to be patched
                Emit(OP_JUMP_IF_FALSE);
                Emit(0);
                Emit(0);
                loopEndJmpAddr := getOffSet - 2;
                Gen(Expr.List[2]); // compile body
                // goto loop start
                Emit(OP_JUMP);
                Emit(0);
                Emit(0);
                patchJumpAddress(getOffSet - 2, loopStartAddr);
                loopEndAddr := getOffSet + 1;
                patchJumpAddress(loopEndJmpAddr, loopEndAddr);
              end
            else if Op = 'for' then
              begin
                Gen(Expr.List[1]); // initializer: (var i 0)
                loopStartAddr := getOffSet;
                Gen(Expr.List[2]); // test condition
                // loop end, Init with 0 address, to be patched
                Emit(OP_JUMP_IF_FALSE);
                Emit(0);
                Emit(0);
                loopEndJmpAddr := getOffSet - 2;
                Gen(Expr.List[4]); // body (begin ... )
                Gen(Expr.List[3]); // iterator (+ i 1)
                // goto loop start
                Emit(OP_JUMP);
                Emit(0);
                Emit(0);
                patchJumpAddress(getOffSet - 2, loopStartAddr);
                loopEndAddr := getOffSet + 1;
                patchJumpAddress(loopEndJmpAddr, loopEndAddr);
              end
            else if Op = 'var' then
              // Variable decl: ( var x (+ y 10) )
              begin
                VarName := Expr.List[1].Str;

                opCodeSetter := ScopeStack_.Peek^.getNameSetter(VarName);

                // special treatment of (var foo (lambda...
                // to capture function name from variable
                if isLambda(Expr.List[2]) then
                  compileFunction(Expr.List[2], VarName, Expr.List[2].List[1], Expr.List[2].List[2])
                else
                  Gen(Expr.List[2]); // initializer

                if opCodeSetter = OP_SET_GLOBAL then             // 1. Global vars
                  begin
                    Global^.Define(VarName);
                    Emit(OP_SET_GLOBAL);
                    Emit(Global^.getGlobalIndex(VarName));
                  end
                else if opCodeSetter = OP_SET_CELL then          // 2. cell vars
                  begin
                    CO.cellNames.Add(VarName);
                    Emit(OP_SET_CELL);
                    Emit(CO.cellNames.Count - 1);
                    // explicitly pop the value from the stack,
                    // since it is promoted to the heap.
                    Emit(OP_POP);
                  end
                else                                             // 3. Local vars
                  begin
                    CO.addLocal(VarName);
                    // Note: no need to explicitly set the var value since the
                    // initializer is already on the stack at the needed slot
                    //Emit(OP_SET_LOCAL);
                    //Emit(CO.getLocalIndex(VarName));
                  end;
              end
            else if Op = 'set' then
              // Variable assignment: ( set x (+ y 10) )
              begin
                VarName := Expr.List[1].Str;

                opCodeSetter := ScopeStack_.Peek^.getNameSetter(VarName);

                // assignment value
                Gen(Expr.List[2]);

                // 1. Local vars first
                if opCodeSetter = OP_SET_LOCAL then
                  begin
                    Emit(OP_SET_LOCAL);
                    Emit(CO.getLocalIndex(VarName));
                  end

                // 2. Cell vars
                else if opCodeSetter = OP_SET_CELL then
                  begin
                    Emit(OP_SET_CELL);
                    Emit(CO.getCellIndex(VarName));
                  end

                // 3. Global vars
                else
                  begin
                    GlobalIndex := Global^.getGlobalIndex(VarName);
                    if GlobalIndex = -1 then
                      begin
                        Writeln('[Compiler]: Reference error: ', VarName, ' is not defined.');
                        Halt;
                      end;
                      Emit(OP_SET_GLOBAL);
                      Emit(GlobalIndex);
                  end;
              end
            else if Op = 'begin' then // blocks
              begin
                ScopeStack_.Push(ScopeInfo_[Expr]);
                BlockEnter;
                // compile each expression inside the block
                for i := 1 to Expr.List.Count - 1 do
                  begin
                    // Value of last expression is kept on the stack
                    isLast := i = Expr.List.Count - 1;
                    // Local variable or function should not Pop
                    //isLocalDecl := isDeclaration(Expr.List[i]) and (not isGlobalScope);
                    isDecl := isDeclaration(Expr.List[i]);
                    Gen(Expr.List[i]);  // Generate expression code
                    if (not isLast) and (not isDecl) then
                      Emit(OP_POP);
                  end;

                BlockExit;
                Dispose(ScopeStack_.Pop);
              end
            // function declaration: (def <name> <params> <body>)
            // which in fact is syntactic sugar for:
            // (var <name> (lambda <params> <body>) )
            else if Op = 'def' then
              begin
                fnName := Expr.List[1].Str;   // function name

                //              Expr, Name,   Parameters,   Body
                compileFunction(Expr, fnName, Expr.List[2], Expr.List[3]);

                if isGlobalScope then
                  begin
                    Global^.Define(fnName);
                    Emit(OP_SET_GLOBAL);
                    Emit(Global^.getGlobalIndex(fnName));
                  end
                else
                  begin
                    CO.addLocal(fnName);
                    // no neeed to expicitly set the local var value since the
                    // function is already on the stack in the needed slot
                    //Emit(OP_SET_LOCAL);
                    //Emit(CO.getLocalIndex(fnName));
                  end;
              end
             // lambda expression: (lambda (a b) (+ a b))
             else if Op = 'lambda' then
              begin
                compileFunction(Expr, 'lambda', Expr.List[1], Expr.List[2]);
              end
            else  // otherwise it's a function call, e.g. (sqr 2)
              begin
                // push function onto the stack
                Gen(Expr.List[0]);
                // Arguments
                for i := 1 to Expr.List.Count - 1 do
                  Gen(Expr.List[i]);
                Emit(OP_CALL);
                Emit(Expr.List.Count - 1); // number of arguments
              end
          end
        else
          // lambda funcion calls: e.g. ((lambda (x) (* x x)) 2)
          begin
            // push function onto the stack
            Gen(Expr.List[0]);
            // Arguments
            for i := 1 to Expr.List.Count - 1 do
              Gen(Expr.List[i]);
            Emit(OP_CALL);
            Emit(Expr.List.Count - 1); // number of arguments
          end
      end;
  end;
end;

procedure TCompiler.DisassembleBytecode;
var
  CO_: TCodeObj;
begin
  Disassembler.Init(Global);
  for CO_ in CodeObjects do
    Disassembler.Disassemble(CO_);
end;

procedure TCompiler.Emit(Code: Byte);
begin
  CO.Code.Add(Code);
end;

function TCompiler.NumericConstIdx(const Value: Double): Integer;
var
  i: Integer;
begin
  for i:=0 to CO.Constants.Count - 1 do
    begin
      if not isNum(CO.Constants[i]) then
        Continue;
      if asNum(CO.Constants[i]) = Value then
        Exit(i);
    end;
  CO.addConst(NumVal(Value));
  Result := CO.Constants.Count - 1;
end;

function TCompiler.StringConstIdx(const Value: String): Integer;
var
  i: Integer;
begin
  for i:=0 to CO.Constants.Count - 1 do
    begin
      if not isString(CO.Constants[i]) then
        Continue;
      if asPasString(CO.Constants[i]) = Value then
        Exit(i);
    end;
  CO.addConst(AllocString(Value));
  Result := CO.Constants.Count - 1;
end;

function TCompiler.BooleanConstIdx(const Value: Boolean): Integer;
var
  i: Integer;
begin
  for i:=0 to CO.Constants.Count - 1 do
    begin
      if not isBool(CO.Constants[i]) then
        Continue;
      if asBool(CO.Constants[i]) = Value then
        Exit(i);
    end;
  CO.addConst(BoolVal(Value));
  Result := CO.Constants.Count - 1;
end;

procedure TCompiler.GenBinaryOp(const Op: Byte; Expr1, Expr2: TExpr);
begin
  Gen(Expr1);
  Gen(Expr2);
  Emit(Op);
end;

function TCompiler.getOffSet: Integer;
begin
  Result := CO.Code.Count;
end;

procedure TCompiler.writeByteAtOffSet(OffSet: Integer; Value: Byte);
begin
  CO.Code[OffSet] := Value;
end;

procedure TCompiler.patchJumpAddress(OffSet: Integer; Value: UInt16);
begin
  writeByteAtOffSet(OffSet, (Value shr 8) and $ff);
  writeByteAtOffSet(OffSet + 1, Value and $ff);
end;

procedure TCompiler.BlockEnter;
begin
  // Increment scope level when entering a new scope
  Inc(CO.ScopeLevel);
end;

procedure TCompiler.BlockExit;
var
  VarsCount: Byte;
begin
  // Pop variables from the stack if declared in this scope
  VarsCount := getVarsCountOnScopeExit;
  if (VarsCount > 0) or (CO.Arity > 0) then
    begin
      Emit(OP_SCOPE_EXIT);

      // for function do callee cleanup: pop arguments + function name
      if isFunctionBody then
        VarsCount += CO.Arity + 1;

      Emit(VarsCount);
    end;

  Dec(CO.ScopeLevel);
end;

// create new code object
function TCompiler.CreateCodeObjectValue(const Name: ShortString;
  const Arity: Integer): TValue;
var
  coValue: TValue;
  Code: TCodeObj;
begin
  coValue := AllocCode(Name, Arity);
  Code := asCode(coValue);
  CodeObjects.Add(Code);
  Result := coValue;
end;

function TCompiler.isGlobalScope: Boolean;
begin
  Result := (CO.Name = 'main') and (CO.ScopeLevel = 1);
end;

function TCompiler.isFunctionBody: Boolean;
begin
  Result := (CO.Name <> 'main') and (CO.ScopeLevel = 1);
end;

function TCompiler.isDeclaration(Expr: TExpr): Boolean;
begin
  Result := isVarDeclaration(Expr) or isDefDeclaration(Expr);
end;

function TCompiler.isVarDeclaration(Expr: TExpr): Boolean;
begin
  Result := isTaggedList(Expr, 'var');
end;

function TCompiler.isDefDeclaration(Expr: TExpr): Boolean;
begin
  Result := isTaggedList(Expr, 'def');
end;

function TCompiler.isLambda(Expr: TExpr): Boolean;
begin
  Result := isTaggedList(Expr, 'lambda');
end;

function TCompiler.isBlock(Expr: TExpr): Boolean;
begin
  Result := isTaggedList(Expr, 'begin');
end;

function TCompiler.isTaggedList(Expr: TExpr; const Tag: ShortString): Boolean;
begin
  Result := (Expr.Typ = etList) and
            (Expr.List[0].Typ = etSymbol) and
            (Expr.List[0].Str = Tag);
end;

function TCompiler.getVarsCountOnScopeExit: Integer;
begin
  Result := 0;
  if CO.Locals.Count > 0 then
    while (CO.Locals.Count > 0) and (CO.Locals.Last^.ScopeLevel = CO.ScopeLevel) do
      begin
        CO.Locals.Delete(CO.Locals.Count-1);
        Inc(Result);
      end;
    //while (CO.Locals.Count > 0) and (CO.Locals.Last.ScopeLevel = CO.ScopeLevel) do
    //  begin
    //    CO.Locals.Remove(CO.Locals.Last);
    //    Inc(Result);
    //  end;
end;

procedure TCompiler.compileFunction(Expr: TExpr; const fnName: ShortString;
  Params: TExpr; Body: TExpr);
var
  prevCO: TCodeObj;
  coValue, Func: TValue;
  i, Arity, cellIndex: Integer;
  argName, freeVar: ShortString;
  scopeInfo: PScope;
begin
  scopeInfo := scopeInfo_[Expr];
  ScopeStack_.Push(scopeInfo);
  Arity := Params.List.Count;        // number of parameters
  prevCO := CO;  // save previous code object
  coValue := CreateCodeObjectValue(fnName, Arity);  // function code object
  CO := asCode(coValue);
  // Put 'free' and 'cells' from the scope into the cellNames of the code object
  CO.freeCount := scopeInfo^.FreeVar.Count;

  CO.CellNames.Capacity := ScopeInfo^.FreeVar.Count + ScopeInfo^.Cells.Count;
  CO.CellNames.InsertRange(CO.CellNames.Count, ScopeInfo^.FreeVar);
  CO.CellNames.InsertRange(CO.CellNames.Count, ScopeInfo^.Cells);

  // store new CO as a constant
  prevCO.addConst(coValue);
  // function name is registered as a local so it can call itself recursively
  CO.addLocal(fnName);
  // the parameters are added as variables
  for i := 0 to Arity - 1 do
    begin
      argName := Params.List[i].Str;
      CO.addLocal(argName);
      // Note: if the param is captured by cell, emit the code for it. We also don't
      // pop the param value in this case, since OP_SCOP_EXIT would pop it.
      cellIndex := CO.getCellIndex(argName);
      if cellIndex <> -1 then
        begin
          Emit(OP_SET_CELL_PARAM);
          Emit(cellIndex);
        end;
    end;
  // compile body in the new code object
  Gen(Body);
  // if we don't have an explicit block which pops locals
  // we should pop arguments (if any)  - callee cleanup
  // + 1 is for the function itself which is set as a local.
  if not isBlock(Body) then
    begin
      Emit(OP_SCOPE_EXIT);
      Emit(Arity + 1);
    end;
  // explicit return to restore caller address
  Emit(OP_RETURN);

  // 1. Simple functions (allocated at compile time)
  // If it's not a closure (i.e. this function doesn't have free variables),
  // allocate it at compile time and store as a constant. Closures are allocated
  // at runtime, but reuse the same code object.
  if scopeInfo^.FreeVar.Count = 0 then
    begin
      // create the function
      Func := AllocFunction(CO);
      // restore the code object
      CO := prevCO;
      // add function as a constant to our CO
      CO.addConst(Func);
      // emit code for this new constant
      Emit(OP_CONST);
      Emit(CO.Constants.Count - 1);
    end
  else
    // 2. Closures:
    // a. load all free vars to capture (indices are taken from the cells of the parent CO)
    // b. load code object for the current function
    // c. make function
    begin
      // restore the code object
      CO := prevCO;
      for freeVar in scopeInfo^.FreeVar do
        begin
          Emit(OP_LOAD_CELL);
          Emit(prevCO.getCellIndex(freeVar));
        end;
      // Load code objects
      Emit(OP_CONST);
      Emit(CO.Constants.Count - 1);

      // Create the function
      Emit(OP_MAKE_FUNCTION);
      // How many cells to capture
      Emit(scopeInfo^.FreeVar.Count);
    end;

  Dispose(ScopeStack_.Pop);
end;

procedure TCompiler.Analyze(Expr: TExpr; Scope: PScope);
var
  Tag: TExpr;
  Op, fnName: String;
  i, Arity: Integer;
  newScope: PScope;
begin
  if Expr.Typ = etSymbol then
    begin
      if (Expr.Str = 'true') or (Expr.Str = 'false') then
        // do nothing
      else
        Scope^.maybePromote(Expr.Str);
    end
  else if Expr.Typ = etList then
    begin
      Tag := Expr.List[0];
      // special cases
      if Tag.Typ = etSymbol then
        begin
          Op := Tag.Str;
          // Block scope
          if Op = 'begin' then
            begin
              New(newScope);
              newScope^.Init(IfThen(Scope=Nil, stGlobal, stBlock), Scope);
              ScopeInfo_.AddOrSetValue(Expr, newScope);
              for i := 1 to Expr.List.Count - 1 do
                Analyze(Expr.List[i], newScope);
            end
          else if Op = 'var' then
            begin
              Scope^.addLocal(Expr.List[1].Str);
              Analyze(Expr.List[2], Scope);
            end
          else if Op = 'def' then
            begin
              fnName := Expr.List[1].Str;
              Scope^.addLocal(fnName);
              New(newScope);
              newScope^.Init(stFunction, Scope);
              ScopeInfo_.AddOrSetValue(Expr, newScope);
              newScope^.addLocal(fnName);
              Arity := Expr.List[2].List.Count;
              for i := 0 to Arity - 1 do
                newScope^.addLocal(Expr.List[2].List[i].Str);

              Analyze(Expr.List[3], newScope);   // analyze body
            end
          else if Op = 'lambda' then
            begin
              New(newScope);
              newScope^.Init(stFunction, Scope);
              ScopeInfo_.AddOrSetValue(Expr, newScope);
              Arity := Expr.List[1].List.Count;
              for i := 0 to Arity - 1 do
                newScope^.addLocal(Expr.List[1].List[i].Str);
              // body
              Analyze(Expr.List[2], newScope);
            end
          else
            for i := 1 to Expr.List.Count - 1 do
              Analyze(Expr.List[i], Scope);
        end
      else
        for i := 0 to Expr.List.Count - 1 do
          Analyze(Expr.List[i], Scope);
    end;
end;


end.

