--		Copyright 1994-2000 by Daniel R. Grayson

newStartupMethod := true;				    -- for testing purposes

use C;
use system;
use actors;
use convertr;
use evaluate;
use common;
use binding;
use actors2;
use actors3;
use actors4;
use actors5;
use parser;
use lex;
use gmp;
use nets;
use tokens;
use err;
use stdiop;
use ctype;
use stdio;
use varstrin;
use strings;
use objects;
use basic;
use struct;
use texmacs;

import dirname(s:string):string;

fileExitHooks := setupvar("fileExitHooks", Expr(emptyList));
currentFileName := setupvar("currentFileName", nullE);
currentPosFile  := dummyPosFile;
currentFileDirectory := setupvar("currentFileDirectory", Expr("./"));
update(err:Error,prefix:string,f:Code):Expr := (
     if err.position == dummyPosition
     then printErrorMessageE(f,prefix + ": " + err.message)
     else printErrorMessageE(f,prefix + ": --backtrace update-- ")
     );
previousLineNumber := -1;

BeforeEval := makeProtectedSymbolClosure("BeforeEval");
AfterEval := makeProtectedSymbolClosure("AfterEval");
BeforePrint := makeProtectedSymbolClosure("BeforePrint");
Print := makeProtectedSymbolClosure("Print");
NoPrint := makeProtectedSymbolClosure("NoPrint");
AfterPrint := makeProtectedSymbolClosure("AfterPrint");
AfterNoPrint := makeProtectedSymbolClosure("AfterNoPrint");
runmethod(methodname:SymbolClosure,g:Expr):Expr := (
     method := lookup(Class(g),methodname);
     if method == nullE then g else applyEE(method,g)
     );
runmethod(methodname:Expr,g:Expr):Expr := (
     method := lookup(Class(g),methodname);
     if method == nullE then g else applyEE(method,g)
     );

endInput := makeProtectedSymbolClosure("end");

PrintOut(g:Expr,semi:bool,f:Code):Expr := (
     methodname := if semi then NoPrint else Print;
     method := lookup(Class(g),methodname);
     if method == nullE 
     then printErrorMessageE(f,"no method for '" + methodname.symbol.word.name + "'")
     else applyEE(method,g)
     );
readeval4(file:TokenFile,printout:bool,dictionary:Dictionary,returnLastvalue:bool,stopIfBreakReturnContinue:bool,returnIfError:bool):Expr := (
     lastvalue := nullE;
     mode := topLevelMode;
     modeBeforePrint := list(mode,Expr(BeforePrint));
     modeNoPrint := list(mode,Expr(NoPrint));
     modePrint := list(mode,Expr(Print));
     modeAfterNoPrint := list(mode,Expr(AfterNoPrint));
     modeAfterPrint := list(mode,Expr(AfterPrint));
     bumpLineNumber := true;
     promptWanted := false;
     issuePrompt := false;
     while true do (
	  if debugLevel == 123 then stderr <<  "------------ top of loop" << endl;
	  if bumpLineNumber then (
	       if debugLevel == 123 then stderr <<  "-- bumpLineNumber" << endl;
     	       if printout then setLineNumber(lineNumber + 1);
	       bumpLineNumber = false;
	       );
	  if promptWanted then (
	       if debugLevel == 123 then stderr <<  "-- promptWanted" << endl;
     	       previousLineNumber = -1;	-- to force a prompt at the beginning of the next input line
	       promptWanted = false;
	       );
	  if issuePrompt then (
	       if debugLevel == 123 then stderr <<  "-- issuePrompt" << endl;
	       previousLineNumber = -1;
	       stdout << file.posFile.file.prompt();
	       issuePrompt = false;
	       );
	  clearAllFlags();
	  if debugLevel == 123 then (
	       stderr << "-- file: " << file.posFile.filename << ":" << file.posFile.line << ":" << file.posFile.column << endl;
	       c := peek(file.posFile.file);
	       stderr << "-- next character: ";
	       if c == int('\n') then stderr << "NEWLINE" else if c >= 0 then stderr << char(c) else stderr << c;
	       stderr << endl;
	       );
	  u := peektoken(file,true);
	  interruptPending = false; determineExceptionFlag();
	  if u == errorToken || interruptedFlag then (
	       gettoken(file,true);
	       if interruptedFlag then (
		    if debugLevel == 123 then stderr <<  "-- token read interrupted" << endl;
		    clearFileError(file);
	       	    interruptedFlag = false; determineExceptionFlag();
		    promptWanted = true;
		    issuePrompt = true;
		    )
	       else (
		    if debugLevel == 123 then stderr <<  "-- token read error" << endl;
		    promptWanted = true;
	       	    if fileError(file) then return buildErrorPacket(fileErrorMessage(file));
	       	    if stopIfError || returnIfError then return buildErrorPacket("--backtrace: token read error--");
		    )
	       )
	  else (
	       t := u.word;
	       if t == wordEOF then (
		    if debugLevel == 123 then stderr <<  "-- EOF token, returning: " << position(u) << endl;
		    return if returnLastvalue then lastvalue else nullE;
		    )
	       else if t == NewlineW then (
		    if debugLevel == 123 then stderr <<  "-- newline token, discarding: " << position(u) << endl;
		    gettoken(file,true);
		    )
	       else if t == wordEOC then (
		    if debugLevel == 123 then stderr <<  "-- end-of-cell token, discarding: " << position(u) << endl;
		    gettoken(file,true);
		    )
	       else (
	  	    previousLineNumber = lineNumber;
		    promptWanted = true;
		    if debugLevel == 123 then stderr <<  "-- ordinary token, ready to parse: " << position(u) << endl;
		    parsed := parse(file,SemicolonW.parse.precedence,true);
		    if parsed == errorTree then (
			 if interruptedFlag then (
		    	      if debugLevel == 123 then stderr <<  "-- parsing interrupted" << endl;
		    	      clearFileError(file);
	       	    	      interruptedFlag = false; determineExceptionFlag();
			      promptWanted = true;
			      -- issuePrompt = true;
			      )
			 else (
		    	      if debugLevel == 123 then stderr <<  "-- error during parsing" << endl;
			      if fileError(file) then return buildErrorPacket(fileErrorMessage(file));
			      if stopIfError || returnIfError then return buildErrorPacket("--backtrace: parse error--");
			      );
			 )
		    else (
			 if debugLevel == 123 then stderr <<  "-- parsing successful" << endl;
		    	 if debugLevel == 123 then stderr << "-- parse tree size: " << size(parsed) << endl;
     	       	    	 bumpLineNumber = true;
			 -- { [ (
			 -- get the token that terminated the parsing of the expression
			 -- it has parsing precedence at most that of the semicolon
			 -- so it is end of file, end of cell, newline, semicolon, or one of the right parentheses : ) ] } 
			 -- that explains the next error message
			 s := gettoken(file,true);
			 if !(s.word == SemicolonW || s.word == NewlineW || s.word == wordEOC || s.word == wordEOF)
			 then (
			      msg := "syntax error: unmatched " + s.word.name;
			      printErrorMessage(s,msg);
			      if stopIfError || returnIfError then return Expr(Error(position(s),msg,nullE,false,dummyFrame));
			      )
			 else (
			      if localBind(parsed,dictionary) -- assign scopes to tokens, look up symbols
			      then (		  
				   -- result of BeforeEval is ignored unless error:
				   -- BeforeEval method is independent of mode
				   f := convert(parsed); -- convert to runnable code
				   be := runmethod(BeforeEval,nullE);
				   when be is err:Error do ( be = update(err,"before eval",f); if stopIfError || returnIfError then return be; ) else nothing;
				   lastvalue = evalexcept(f);	  -- run it
				   if lastvalue == endInput then return nullE;
				   -- when f is globalAssignmentCode do lastvalue = nullE else nothing;
				   when lastvalue is err:Error do (
					if err.message == returnMessage
					|| err.message == continueMessage || err.message == continueMessageWithArg 
					|| err.message == stepMessage || err.message == stepMessageWithArg 
					|| err.message == breakMessage || err.message == throwMessage then (
					     if stopIfBreakReturnContinue then return lastvalue;
					     );
					if err.message == unwindMessage then (
					     lastvalue = nullE;
					     )
					else (
					     if !err.printed then printErrorMessage(err);
					     if stopIfError || returnIfError then return lastvalue;
					     );
					)
				   else (
					if printout then (
					     if mode != topLevelMode then (
						  mode = topLevelMode;
						  modeBeforePrint = list(mode,Expr(BeforePrint));
						  modeNoPrint = list(mode,Expr(NoPrint));
						  modePrint = list(mode,Expr(Print));
						  modeAfterNoPrint = list(mode,Expr(AfterNoPrint));
						  modeAfterPrint = list(mode,Expr(AfterPrint));
						  );
					     -- result of AfterEval replaces lastvalue unless error, in which case 'null' replaces it:
					     g := runmethod(AfterEval,lastvalue);
					     when g is err:Error
					     do (
						  g = update(err,"after eval",f); 
						  if stopIfError || returnIfError then return g;
						  lastvalue = nullE;
						  ) 
					     else lastvalue = g;
					     -- result of BeforePrint is printed instead unless error:
					     printvalue := nullE;
					     g = runmethod(modeBeforePrint,lastvalue);
					     when g is err:Error
					     do ( g = update(err,"before print",f); if stopIfError || returnIfError then return g; )
					     else printvalue = g;
					     -- result of Print is ignored:
					     g = runmethod(if s.word == SemicolonW then modeNoPrint else modePrint,printvalue);
					     when g is err:Error do ( g = update(err,"at print",f); if stopIfError || returnIfError then return g; ) else nothing;
					     -- result of AfterPrint is ignored:
					     g = runmethod(if s.word == SemicolonW then modeAfterNoPrint else modeAfterPrint,lastvalue);
					     when g is err:Error do ( g = update(err,"after print",f); if stopIfError || returnIfError then return g; ) else nothing;
					     )
					)
				   )
			      else if isatty(file) 
			      then flush(file)
			      else return buildErrorPacket("error while loading file")))))));

interpreterDepthS := setupvar("interpreterDepth",toExpr(0));
incrementInterpreterDepth():void := (
     interpreterDepth = interpreterDepth + 1;
     setGlobalVariable(interpreterDepthS,toExpr(interpreterDepth)));
decrementInterpreterDepth():void := (
     interpreterDepth = interpreterDepth - 1;
     setGlobalVariable(interpreterDepthS,toExpr(interpreterDepth)));


readeval3(file:TokenFile,printout:bool,dc:DictionaryClosure,returnLastvalue:bool,stopIfBreakReturnContinue:bool,returnIfError:bool):Expr := (
     saveLocalFrame := threadLocalInterpState.localFrame;
     threadLocalInterpState.localFrame = dc.frame;
      savecf := getGlobalVariable(currentFileName);
      savecd := getGlobalVariable(currentFileDirectory);
      savepf := currentPosFile;
	setGlobalVariable(currentFileName,Expr(file.posFile.file.filename));
	setGlobalVariable(currentFileDirectory,Expr(dirname(file.posFile.file.filename)));
        currentPosFile = file.posFile;
	ret := readeval4(file,printout,dc.dictionary,returnLastvalue,stopIfBreakReturnContinue,returnIfError);
      setGlobalVariable(currentFileDirectory,savecd);
      setGlobalVariable(currentFileName,savecf);
      currentPosFile = savepf;
     threadLocalInterpState.localFrame = saveLocalFrame;
     ret);
readeval(file:TokenFile,returnLastvalue:bool,returnIfError:bool):Expr := (
     savefe := getGlobalVariable(fileExitHooks);
     setGlobalVariable(fileExitHooks,emptyList);
     printout := false; mode := nullE;
     ret := readeval3(file,printout,newStaticLocalDictionaryClosure(file.posFile.file.filename),returnLastvalue,false,returnIfError);
     haderror := when ret is Error do True else False;
     hadexiterror := false;
     hook := getGlobalVariable(fileExitHooks);
     when hook is x:List do foreach f in x.v do (
	  r := applyEE(f,haderror);
	  when r is err:Error do (
	       if err.position == dummyPosition then stderr << "error in file exit hook: " << err.message << endl;
	       hadexiterror = true;
	       ) else nothing
	  )
     else nothing;
     setGlobalVariable(fileExitHooks,savefe);
     if hadexiterror then buildErrorPacket("error in file exit hook") else ret);

InputPrompt := makeProtectedSymbolClosure("InputPrompt");
InputContinuationPrompt := makeProtectedSymbolClosure("InputContinuationPrompt");

promptcount := 0;
topLevelPrompt():string := (
     if debugLevel == 123 then (
	  stderr <<  "-- topLevelPrompt:" 
	  << " previousLineNumber = " << previousLineNumber 
	  << "; lineNumber = " << lineNumber 
	  << endl;
	  );
     method := lookup(
	  ZZClass,
	  list(topLevelMode, Expr(if lineNumber == previousLineNumber then InputContinuationPrompt else (previousLineNumber = lineNumber; InputPrompt))));
     p := (
	  if method == nullE then ""
     	  else when applyEE(method,toExpr(lineNumber)) is s:string do s
     	  is n:ZZ do if isInt(n) then blanks(toInt(n)) else ""
     	  else "\n<--bad prompt--> : " -- unfortunately, we are not printing the error message!
	  );
     if debugLevel == 123 then (
	  p = "[" + tostring(promptcount) + "]  " + p;
	  stderr <<  "-- topLevelPrompt:" 
	  << " prompt = \"" << present(p) << "\""
	  << endl;
	  );
     promptcount = promptcount + 1;
     p);

loadprintstdin(dc:DictionaryClosure,stopIfBreakReturnContinue:bool,returnIfError:bool):Expr := (
     when openTokenFile("-")
     is e:errmsg do buildErrorPacket(e.message)
     is file:TokenFile do (
	  if !file.posFile.file.fulllines		    --texmacs !
	  then setprompt(file,topLevelPrompt);
	  r := readeval3(file,true,dc,false,stopIfBreakReturnContinue,returnIfError);
	  file.posFile.file.eof = false; -- erase eof indication so we can try again (e.g., recursive calls to topLevel)
	  r));

loadprint(filename:string,dc:DictionaryClosure,returnIfError:bool):Expr := (
     when openTokenFile(filename)
     is errmsg do False
     is file:TokenFile do (
	  if file.posFile.file != stdin then file.posFile.file.echo = true;
	  if !file.posFile.file.fulllines		    --texmacs !
	  then setprompt(file,topLevelPrompt);
	  r := readeval3(file,true,dc,false,false,returnIfError);
	  t := (
	       if filename === "-"			 -- whether it's stdin
	       then (
		    file.posFile.file.eof = false; -- erase eof indication so we can try again (e.g., recursive calls to topLevel)
		    0
		    )
	       else close(file));
	  when r is err:Error do (
	       if err.message == returnMessage
	       || err.message == continueMessage || err.message == continueMessageWithArg
	       || err.message == stepMessage || err.message == stepMessageWithArg
	       || err.message == breakMessage then if err.value == dummyExpr then nullE else err.value else r
	       )
	  else (
	       if t == ERROR
	       then buildErrorPacket("error closing file") 
	       else nullE)));
load(filename:string):Expr := (
     when openTokenFile(filename)
     is e:errmsg do buildErrorPacket(e.message)
     is file:TokenFile do (
	  r := readeval(file,true,true);
	  t := if !(filename==="-") then close(file) else 0;
	  when r is err:Error do (
	       if err.message == returnMessage
	       || err.message == continueMessage || err.message == continueMessageWithArg
	       || err.message == stepMessage || err.message == stepMessageWithArg
	       || err.message == breakMessage then if err.value == dummyExpr then nullE else err.value else r
	       )
	  else (
	       if t == ERROR
	       then buildErrorPacket("error closing file") 
 	       else r)));

load(e:Expr):Expr := (
     when e
     is s:string do load(s)
     else buildErrorPacket("expected string as file name"));
setupfun("simpleLoad",load);

currentLineNumber(e:Expr):Expr := (
     when e is s:Sequence do
     if length(s) == 0 then Expr(toInteger(int(currentPosFile.line)))
     else WrongNumArgs(0)
     else WrongNumArgs(0));
setupfun("currentLineNumber",currentLineNumber);

input(e:Expr):Expr := (
     when e
     is filename:string do (
	  -- we should have a way of setting normal prompts while inputting
     	  incrementInterpreterDepth();
	  ret := loadprint(filename,newStaticLocalDictionaryClosure(filename),true);
     	  decrementInterpreterDepth();
	  previousLineNumber = -1;
	  ret)
     else buildErrorPacket("expected string as file name"));
setupfun("simpleInput",input);

stringTokenFile(name:string,contents:string):TokenFile := (
     TokenFile(
	  makePosFile(
	  file(nextHash(),     	    	  -- hash
	       name,	 		  -- filename
	       0,			  -- pid
	       false,	       	    	  -- error
	       "",     	    	      	  -- message
	       false,	       	    	  -- listener
	       NOFD,   	    	          -- listenerfd
	       NOFD,	      	   	  -- connection
	       0,     	   	     	  -- numconns
	       true,			  -- input
	       NOFD,			  -- infd
	       false,			  -- inisatty
	       contents,		  -- inbuffer
	       0,			  -- inindex
	       length(contents),	  -- insize
	       true,			  -- eof
	       false,	  		  -- promptq
	       noprompt,		  -- prompt
	       noprompt,		  -- reward
	       false,			  -- fulllines
     	       true,	       	    	  -- bol
	       false,			  -- echo
	       0,			  -- echoindex
	       false,			  -- output
	       NOFD,			  -- outfd
	       false,			  -- outisatty
	       "",			  -- outbuffer
	       0,			  -- outindex
	       0,     	   	     	  -- outbol
	       false,	       	    	  -- hadNet
	       dummyNetList,   	      	  -- nets
	       0,		          -- bytesWritten
	       -1,		          -- lastCharOut
	       false                      -- readline
	       )),
	  NULL));

export topLevel():bool := (
     when loadprint("-",newStaticLocalDictionaryClosure(),false)
     is err:Error do (
	  -- printErrorMessage(err);		    -- this message may not have been printed before (?)
	  false)
     else true
     );

commandInterpreter(dc:DictionaryClosure):Expr := loadprint("-",dc,false);
commandInterpreter(f:Frame):Expr := commandInterpreter(newStaticLocalDictionaryClosure(localDictionaryClosure(f)));
commandInterpreter(e:Expr):Expr := (
     --saveLoadDepth := loadDepth;
     --setLoadDepth(loadDepth+1);
     incrementInterpreterDepth();
       ret := 
       when e is s:Sequence do (
	    if length(s) == 0 then loadprint("-",newStaticLocalDictionaryClosure(),false)
	    else WrongNumArgs(0,1)
	    )
       is Nothing do loadprint("-",newStaticLocalDictionaryClosure(),false)
       is x:DictionaryClosure do commandInterpreter(x)
       is x:SymbolClosure do commandInterpreter(x.frame)
       is x:CodeClosure do commandInterpreter(x.frame)
       is x:FunctionClosure do commandInterpreter(x.frame)
       is cfc:CompiledFunctionClosure do commandInterpreter(emptyFrame)	    -- some values are there, but no symbols
       is CompiledFunction do commandInterpreter(emptyFrame)		    -- no values or symbols are there
       is s:SpecialExpr do commandInterpreter(s.e)
       else WrongArg("a function, symbol, dictionary, pseudocode, or ()");
     decrementInterpreterDepth();
     --setLoadDepth(saveLoadDepth);
     ret);
setupfun("commandInterpreter",commandInterpreter);

currentS := setupvar("current",nullE);
debugger(f:Frame,c:Code):Expr := (
     -- stdIO << "-- recursionDepth = " << recursionDepth << endl;
     oldrecursionDepth := recursionDepth;
     recursionDepth = 0;
     setDebuggingMode(false);
       oldDebuggerCode := getGlobalVariable(currentS);
       setGlobalVariable(currentS,Expr(CodeClosure(f,c)));
	 incrementInterpreterDepth();
	   if debuggerHook != nullE then (
		r := applyEE(debuggerHook,True);
		when r is Error do return r else nothing;
		);
	   ret := loadprintstdin(newStaticLocalDictionaryClosure(localDictionaryClosure(f)),true,false);
	   if debuggerHook != nullE then (
		r := applyEE(debuggerHook,False);
		when r is Error do return r else nothing;
		);
	 decrementInterpreterDepth();
       setGlobalVariable(currentS,oldDebuggerCode);
     setDebuggingMode(true);
     recursionDepth = oldrecursionDepth;
     ret);
debuggerFun = debugger;

currentString := setupvar("currentString", nullE);
value(e:Expr):Expr := (
     when e
     is q:SymbolClosure do q.frame.values.(q.symbol.frameindex)
     is c:CodeClosure do eval(c.frame,c.code)
     is s:string do (
      	  savecs := getGlobalVariable(currentString);
	  setGlobalVariable(currentString,Expr(s));
	  r := readeval(stringTokenFile("currentString", s+newline),true,true);
	  setGlobalVariable(currentString,savecs);
	  when r 
	  is err:Error do (
	       if err.message == returnMessage
	       || err.message == continueMessage || err.message == continueMessageWithArg 
	       || err.message == stepMessage || err.message == stepMessageWithArg 
	       || err.message == breakMessage then if err.value == dummyExpr then nullE else err.value 
	       else r)
	  else r)
     else WrongArg(1,"a string, a symbol, or pseudocode"));
setupfun("value",value).protected = false;

tmpbuf := new string len 100 do provide ' ' ;

internalCapture(e:Expr):Expr := (
     when e
     is s:string do (
     	  flush(stdIO);
	  oldfd := stdIO.outfd;
	  oldDebuggingMode := debuggingMode;
	  setDebuggingMode(false);
	  oldStderrE := getGlobalVariable(stderrS);
	  oldstderr := stderr;
	  stderr = stdIO;
	  setGlobalVariable(stderrS,getGlobalVariable(stdioS));
	  stdIO.outfd = NOFD;
	  oldbuf := stdIO.outbuffer;
	  stdIO.outbuffer = tmpbuf;
	  stringFile := stringTokenFile("currentString", s+newline);
	  stringFile.posFile.file.echo = true;
	  oldLineNumber := lineNumber;
	  previousLineNumber = -1;
	  setLineNumber(0);
	  setprompt(stringFile,topLevelPrompt);
	  r := readeval3(stringFile,true,newStaticLocalDictionaryClosure(),false,false,true);
	  out := substrAlwaysCopy(stdIO.outbuffer,0,stdIO.outindex);
	  stdIO.outfd = oldfd;
	  stdIO.outbuffer = oldbuf;
	  stdIO.outindex = 0;
	  setGlobalVariable(stderrS,oldStderrE);
	  stderr = oldstderr;
	  setLineNumber(oldLineNumber);
	  setDebuggingMode(oldDebuggingMode);
	  previousLineNumber = -1;
	  Expr(Sequence( when r is err:Error do True else False, Expr(out) )))
     else WrongArg(1,"a string"));
setupfun("internalCapture",internalCapture);

normalExit := 0;
errorExit := 1;
interruptExit := 2;					    -- see also M2lib.c
failedExitExit := 3;

Exit(err:Error):void := exit(
     if err.message === interruptMessage then interruptExit
     else errorExit
     );

export process():void := (
     threadLocalInterpState.localFrame = globalFrame;
     previousLineNumber = -1;			  -- might have done dumpdata()
     stdin .inisatty  =   0 != isatty(0) ;
     stdin.echo       = !(0 != isatty(0));
     stdout.outisatty =   0 != isatty(1) ;
     stderr.outisatty =   0 != isatty(2) ;
     setstopIfError(false);				    -- this is usually true after loaddata(), we want to reset it
     sethandleInterrupts(true);
     -- setLoadDepth(loadDepth);				    -- loaddata() in M2lib.c increments it, so we have to reflect that at top level
     everytimeRun();
     -- we don't know the right directory; calls commandInterpreter and eventually returns:
     ret := readeval(stringTokenFile(startupFile,startupString),false,false);
     when ret is err:Error do (
	  if !err.printed then printError(err);		    -- just in case
	  if stopIfError
	  then Exit(err)	 -- probably can't happen, because layout.m2 doesn't set stopIfError
	  else if !topLevel()				    -- give a prompt for debugging
	  then Exit(err))
     else nothing;
     when ret is n:ZZ do (
	  if isInt(n) then (
     	       value(Expr("exit " + tostring(toInt(n))));   -- try to exit the user's way
     	       ))
     else nothing;
     value(Expr("exit 0"));				    -- try to exit the user's way
     exit(failedExitExit);		   -- if that doesn't work, try harder and indicate an error
     );

-- Local Variables:
-- compile-command: "make -C $M2BUILDDIR/Macaulay2/d "
-- End: