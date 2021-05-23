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
    {$define _CHECK_ABORTED := 
        if aborted then
            begin
                __log__( 'Operation was aborted', lmtWARNING 
    }

    // macro for one-line skipping loop iteration with logging
    // example 1: _LOG_MESSAGE 'my log message' AND_CONTINUE_
    // example 2: _LOG_MESSAGE 'my log message' SET_RESULT false AND_CONTINUE_
    {$define _LOG_MESSAGE :=
        begin
            __log__( 
    }

    // this can be used inside _LOG_MESSAGE and _CHECK_ABORTED
    // but not required
    {$define SET_RESULT :=
    );
            result := (
    }

    // only one of the following endings can be used at once
    {$define AND_CONTINUE_ := 
    );
            continue;
        end;
    }
    {$define AND_BREAK_ :=
    );
            break;
        end;
    }

{$endif}