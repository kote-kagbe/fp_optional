# fp_optional
================================Synopsis================================

    Optional type for Free Pascal Compiler
    
===============================Description===============================

    FP lacks some useful types and opportunities many modern programming languages have.
    One of them is optionally set variables. In C++ it can be boost::optional, in Python any variable can be None and so on.
    I managed to find that Warfley's post https://forum.lazarus.freepascal.org/index.php/topic,50478.msg368587.html#msg368587
    Sure it seems like a solution but it uses {$mode delphi} that is not always convenient.
    So inspired by it here is a generic-type wrapper tOptional for {$mode objfpc}.
    
==================================Usage=================================

    Add optional.pas to your project path.
    Add "optional" to "uses" clause.
    Use any ready optional type or declare your own.
    
=================================Details=================================

    Internally tOptional is a record. So one doesn't need to call constructor and destructor.
    Simply use the ready specialized types or make your own:
        type
            tMyOptional = specialize tOptional<any_user_type>;
        var
            my_opt: tMyOptional;
        begin
            my_opt := my_value;
        end;
    One can assign value to each variable simply like it can be done with any other type
        my_opt := value;
    To get the value of the variable use methods Get() and Get( default_value ). If variable is not set then scpecial exception is raised.
    There is no method that checks the state of the variable but one can easily use it as a boolean variable:
        if my_opt then ...
        if not my_opt then ...
    NOTE: it checks the state of the variable, but not it's value! Don't be confused in case of tOptBoolean!
        var
            opt_bool: tOptBoolean;
        begin
            opt_bool := false; // !!!
            if opt_bool then // -> "true" as variable is set
                writeln( opt_bool.get ); // -> "false" as the value is false
    To reset the variable call Reset() method.
               
================================Streaming================================

    For my purpuses I added streaming capabilities so one can write and read optionals from the streams.
    NOTE: For streaming I deliberately limited the size of writable value to 64kB. It adds only 2 bytes overhead to the written data.
        When you needs to store more data better think of specialized storages like lightweight databases for example.
        Nevertheless you can change the type of tMaxDataSizeType to fits your needs. But it would add more overhead.
        THIS RESTRICTION IS ONLY FOR STREAMING, usual in-memory usage is not limited.
        
==========================Streaming user types===========================
    
    If user type is a dynamic size type and one wants to use Read and Write methods then he has to make an optional-type helper for it decaring private function DataSize: longint;
    Otherwise the data size will always be 8 bytes and no useful data will be written or read.
    Check the tOptStringHelper as an example.
    
========================Precautions and licensing=========================

    I haven't yet tested it well so use it on your own risk.
    Any proposals and bugfixes are welcome.
    
    You are free to use it in any project with any license.
    You are free to alter and distibute the optional.pas only without taking fees for it and preserving the authorship.
    The author doesn't respond for any negative consequences probable.
