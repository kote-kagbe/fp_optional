{some macroses for more laconic code}

{$ifdef LOOP_MACRO}
    // macro for one-line abortion check and breaking some loop with logging
    // requires AND_CONTINUE_ or AND_BREAK_ ending
    // can contain SET_RESULT
    // examples: 
    {
        _CHECK_ABORTED AND_CONTINUE_
        _CHECK_ABORTED SET_RESULT false AND_BREAK_
    }
    {$define __CHECK_ABORTED_ := 
        if aborted then
            begin
                __log__( 'Operation was aborted', lmtWARNING 
    }

    // macro for one-line skipping loop iteration with logging
    // example 1: _LOG_MESSAGE 'my log message' AND_CONTINUE_
    // example 2: _LOG_MESSAGE 'my log message' SET_RESULT false AND_CONTINUE_
    {$define __LOG_MESSAGE_ :=
        begin
            __log__( 
    }

    // this can be used inside _LOG_MESSAGE and _CHECK_ABORTED
    // but not required
    {$define _SET_RESULT_ :=
    );
            result := (
    }

    // only one of the following endings can be used at once
    {$define _AND_CONTINUE__ := 
    );
            continue;
        end;
    }
    {$define _AND_BREAK__ :=
    );
            break;
        end;
    }

{$endif}