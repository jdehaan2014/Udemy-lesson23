program gear;

{$mode objfpc}{$H+}

uses
  uVM, uValue, uLogger;

var
  VM: TEvaVM;
  Result: TValue;
begin
  Result := VM.Exec(

  //' (var x 10) ' +       // x global
  //' (def foo () x) ' +  // x global
  ////  ' (foo) ' +
  //' (begin ' +
  //'    (var y 100) ' + // cell
  //'    (set y 1000) ' +
  //'    (var q 300) ' + // local
  //'    q ' +
  //'    (+ x y) ' +   // y: cell, x: global
  //'    (begin ' +
  //'       (var z 200) ' +
  //'        z ' +
  //'       (def bar () (+ y z)) ' +   // cell both
  //'       x)) '
//  '       (bar))) '


'  (def multiplier (n d) '+
'    (begin '+
'      (def multiply (x) (/ (* x n) d)) '+
'      multiply '+
'    ) '+
'  ) '+
'  (var two_thirds (multiplier 2 3)) '+
'  (two_thirds 21) '


    //'  (def createCounter ()      ' +
    //'    (begin ' +
    //'      (var value 0) ' +
    //'      (def inc () (set value (+ value 1))) ' +
    //'      inc)) ' +
    //'  (var fn1 (createCounter)) ' +
    //'  (fn1) ' +
    //'  (fn1) ' +
    //'  (fn1) ' +
    //'  (var fn2 (createCounter)) ' +
    //'  (fn2) ' +
    //'  (+ (fn1) (fn2)) ' +
    //'         '
  );

  VM.dumpStack;

  Log(Result);
  Writeln('All done.');
end.


{

' (var x 10) ' +       // x global
' (def foo () x) ' +  // x global
//  ' (foo) ' +
' (begin ' +
'    (var y 100) ' + // cell
'    (set y 1000) ' +
'    (var q 300) ' + // local
'    q ' +
'    (+ x y) ' +   // y: cell, x: global
'    (begin ' +
'       (var z 200) ' +
'        z ' +
'       (def bar () (+ y z)) ' +   // cell both
'       (bar))) ' +


' (def square (x) (* x x)) ' +
' (square 2) // 4 ' +
' ' +
' (def factorial (x) ' +
'   (if (= x 1) ' +
'      1 ' +
'      (* (factorial (- x 1))))) ' +
' (factorial 5) // 120 '

' (def factorial (x) ' +
'   (if (= x 1) ' +
'      1 ' +
'      (* x (factorial (- x 1))))) ' +
' (factorial 5)   ' // 120


//' (def square (x) (* x x)) ' +
' ((lambda (x) (* x x)) 2) ' +
' (var sq (lambda (x) (* x x))) ' +
' (sq 2) '

'(var x 5)' +
'(set x (+ x 10)) ' +
'x' +
'(begin' +
'  (var z 100)' +
'  (set x 1000)' +
'    (begin' +
'      (var x 200)' +
'     x)' +
'  x)' +
'x'

'(var i 10)' +
'(var count 0) ' +
'(while (> i 0)' +
'(begin' +
'  (set i (- i 1))' +
'  (set count (+ count 1))))' +
'count'

}
