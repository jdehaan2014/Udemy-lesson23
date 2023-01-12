unit uArray;

{$mode delphi}{$H+}
{$PointerMath ON}

interface

uses
  SysUtils;

type

  TArrayList<T> = record
    private type PT = ^T; // define pointer to the type
    private
      fItems: PT;
      fCount: Integer;
      fCapacity: Integer;

      procedure setCapacity(NewCapacity: Integer);

      function getItem(i: Integer): T;
      procedure setItem(i: Integer; AValue: T);

      function getFirst: PT;
      function getLast: PT;

      class operator Initialize(var List: TArrayList<T>);
      class operator Finalize(var List: TArrayList<T>);

    public
      property Items[i:Integer]: T read getItem write setItem; default;
      property Data: PT read fItems write fItems;
      property Count: Integer read fCount;
      property Capacity: Integer read fCapacity write setCapacity;
      property First: PT read getFirst;
      property Last: PT read getLast;
      function Add(AValue: T): Integer;
      procedure AddRange(Values: array of T);
      procedure Delete(const Index: Integer);
  end;

  TByteArray = TArrayList<Byte>;

implementation
uses uCommon;

{ TArrayList }

procedure TArrayList<T>.setCapacity(NewCapacity: Integer);
begin
  if NewCapacity = fCapacity then Exit;

  // reallocate memory, reserve heap space for new capacity
  fItems := ReAllocMem(fItems, SizeOf(T)*NewCapacity);

  // initialize the newly reserved memory space
  FillChar(fItems[fCapacity], (NewCapacity - fCapacity) * SizeOf(T), #0);
  fCapacity := NewCapacity;
end;

function TArrayList<T>.getItem(i: Integer): T;
begin
  // no checking on bounds, so unsafe indexing possible !!!
  Result := fItems[i];
end;

procedure TArrayList<T>.setItem(i: Integer; AValue: T);
begin
  // no checking on bounds, so unsafe indexing possible !!!
  fItems[i] := AValue;
end;

function TArrayList<T>.getFirst: PT;
begin
  If FCount = 0 then
    Result := Nil
  else
    Result := @fItems[0];
end;

function TArrayList<T>.getLast: PT;
begin
  If FCount = 0 then
    Result := Nil
  else
    Result := @fItems[fCount - 1];
end;

class operator TArrayList<T>.Initialize(var List: TArrayList<T>);
begin
  List.fItems := Nil;
  List.fCount := 0;
  List.fCapacity := 0;
end;

class operator TArrayList<T>.Finalize(var List: TArrayList<T>);
begin
  List.fItems := ReAllocMem(List.fItems, 0);
  List.fItems := Nil;
  List.fCount := 0;
  List.fCapacity := 0;
end;

function TArrayList<T>.Add(AValue: T): Integer;
begin
  if fCapacity < (fCount + 1) then
    begin
      fCapacity := IfThen<Integer>(fCapacity < 16, 16, fCapacity * 2);

      // FPC heapmanager auto keeps track of old size.
      fItems := ReAllocMem(fItems, SizeOf(T)*fCapacity);
    end;

  fItems[fCount] := AValue;
  Result := fCount;
  Inc(fCount);
end;

procedure TArrayList<T>.AddRange(Values: array of T);
var
  Size: Integer;
begin
  Size := Length(Values);
  if Size = 0 then Exit;

  Capacity := Capacity + Size;

  System.Move(Values[0], fItems[fCount], SizeOf(T) * Size);
  fCount := fCount + Size;
end;

procedure TArrayList<T>.Delete(const Index: Integer);
var
  ListItem: PT;
begin
  if (Index < 0) or (Index >= fCount) then
    begin
      WriteLnFmt('Index out of list bounds: %d.', [Index]);
      Halt;
    end;
  Dec(fCount);
  ListItem := @fItems[Index];

  System.Move(fItems[Index+1], ListItem^, SizeOf(T) * (fCount - Index));

  // Shrink the list if appropriate
  if (fCapacity > 256) and (fCount < fCapacity shr 2) then
    begin
      fCapacity := fCapacity shr 1;
      fItems := ReallocMem(fItems, fCapacity * SizeOf(T));
    end;

  //FillChar(fItems[fCount], (fCapacity - fCount) * SizeOf(T), #0);
end;

end.

