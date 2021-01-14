:: MIT License
::
:: Copyright (c) 2020 Takumi Kodama
::
:: Permission is hereby granted, free of charge, to any person obtaining a copy
:: of this software and associated documentation files (the "Software"), to deal
:: in the Software without restriction, including without limitation the rights
:: to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
:: copies of the Software, and to permit persons to whom the Software is
:: furnished to do so, subject to the following conditions:
::
:: The above copyright notice and this permission notice shall be included in all
:: copies or substantial portions of the Software.
::
:: THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
:: IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
:: FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
:: AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
:: LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
:: OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
:: SOFTWARE.

:: Development Container start up script for Windows

@echo off
setlocal enabledelayedexpansion
:: get path containing this script
set here=%~dp0
set here=%here:~0,-1%

:: read configs from launch_dev_container.cfg
call :f_read_config image_tag false
if %errorlevel% neq 0 exit /b %errorlevel%
call :f_read_config build_trg false
if %errorlevel% neq 0 exit /b %errorlevel%
call :f_read_config build_ctx false
if %errorlevel% neq 0 exit /b %errorlevel%
call :f_read_config volumes   true
if %errorlevel% neq 0 exit /b %errorlevel%
call :f_read_config run_cmd   false
if %errorlevel% neq 0 exit /b %errorlevel%
:: replace if empty
if "%build_ctx%"=="" set build_ctx=%here%

@REM replace command and arguments
if not defined cmds (
    set run_cmd= %run_cmd%
) else (
    set run_cmd=%cmds%
)


@REM '-h', '--help'
@REM display help text
call :f_read_arg h help && goto :l_print_help

@REM '-e', '--echo', '-E', '--echo-only'
@REM debug mode to display the A command to be executed
call :f_read_arg E echo-only && (
    set echo_cmd1=echo + 
    set echo_cmd2=@rem 
) || call :f_read_arg e echo && (
    set echo_cmd1=echo + 
    set echo_cmd2=
) || (
    set echo_cmd1=
    set echo_cmd2=@rem 
)

@REM '--disable-vol'
@REM disable default volume options
call :f_read_arg ? disable-vol && (
    set i=0
    :s_undef_vol
        if not defined volumes[!i!] goto :e_undef_vol
        set volumes[!i!]=
        set /a i+=1
        goto :s_undef_vol
    :e_undef_vol
    rem
)

@REM '--rm', '-i', '--interactive', '-t', '--tty', '-d', '--detach', '--disable-itd'
set itd=-
call :f_read_arg ? rm &&          set run_opts=%run_opts% %--rm%
call :f_read_arg i interactive && set itd=%itd%i
call :f_read_arg t tty &&         set itd=%itd%t
call :f_read_arg d detach &&      set itd=%itd%d
call :f_read_arg ? disable-itd && (
    rem
) || echo %itd%| findstr "^-$" >NUL 2>&1 && (
    set run_opts=%run_opts% -itd
) || (
    set run_opts=%run_opts% %itd%
)

@REM '-x', '--x11'
@REM x11 options
call :f_read_arg x x11 && (
    set run_opts=%run_opts% -e DISPLAY=host.docker.internal:0
)

@REM '-b', '--build', '-B', '--build-only'
set build_only=FALSE
set build=FALSE
call :f_read_arg b build &&      set build=TRUE
call :f_read_arg B build-only && set build=TRUE&& set build_only=TRUE
if not "%bld_opts%"==""          set build=TRUE
if %build%==FALSE (
    for /f "usebackq" %%A in (`docker images -q %image_tag%`) do set IMGID=%%A
    if "!IMGID!"=="" (
        set build=TRUE
    )
)

@REM '--no-buildkit'
@REM use buildkit feature?
set buildkit_cmd=set DOCKER_BUILDKIT=1

@REM build!
set bld_opts=%bld_opts% -t %image_tag%
if not "%build_trg%"=="" set bld_opts=%bld_opts% --target %build_trg%
if %build%==TRUE (
    %echo_cmd1%%buildkit_cmd%
    %echo_cmd2%%buildkit_cmd%
    %echo_cmd1%docker build%bld_opts% %build_ctx%
    %echo_cmd2%docker build%bld_opts% %build_ctx%
)

@REM volumes
set i=0
:s_setup_volume_opts
    @REM check if defined
    set it=!volumes[%i%]!
    if not defined it goto :e_setup_volume_opts
    set run_opts=%run_opts% -v %it%
    set /a i+=1
    goto :s_setup_volume_opts
:e_setup_volume_opts

@REM run!
%echo_cmd1%docker run%run_opts% %image_tag%%run_cmd%
%echo_cmd2%docker run%run_opts% %image_tag%%run_cmd%

exit /b 0











@REM @param %1 parameter/variable name to read/store
@REM @param %2 true if the paramer is array
:f_read_config
    set rc_cfg_file=%here%\launch_dev_container.cfg
    if not exist %rc_cfg_file% (
        echo fatal error: launch_dev_container.cfg: file not found.
        goto :l_print_fatal_error
    )
    if "%1"=="" (
        echo fatal error: config name must not be empty.
        goto :l_print_fatal_error
    )
    :: calculates the length to be cut from the lines read from the file
    call :f_strlen %1 rc_cutlen
    set /a rc_cutlen+=1
    :: index of the array
    set rc_j=0
    for /f "usebackq" %%A in (`findstr /r "^%1=.*" %rc_cfg_file%`) do (
        set rc_tmp=%%A
        set rc_tmp=!rc_tmp:~%rc_cutlen%!
        if "%2"=="true" (
            set %1[!rc_j!]=!rc_tmp!
        ) else (
            set %1=!rc_tmp!
        )
        set /a rc_j+=1
    )
    exit /b 0

:: Check string length of the first argument.
:: If the second argument is given as a variable name, the length will be stored into the variable.
:: Otherwise, it will be stored into %f_strlen_return%
:: @param %1 string to be checked
:: @param %2 variable name for storing the result (option)
:: @return 0
:f_strlen
    if "%2"=="" (
        set f_strlen_varname=f_strlen_return
    ) else (
        set f_strlen_varname=%2
    )
    set f_strlen_tmp=%1
    set %f_strlen_varname%=0
    :s_loop_f_strlen
        if "%f_strlen_tmp%"=="" goto :e_loop_f_strlen
        set f_strlen_tmp=%f_strlen_tmp:~1%
        set /a %f_strlen_varname%+=1
        goto :s_loop_f_strlen
    :e_loop_f_strlen
    exit /b 0

:f_parse_args
    :: separate all arguments into args, cmds, run_opts, bld_opts
    set nargs=0
    set cmds=
    set run_opts=
    set bld_opts=
    set sep=0
    :S_ARGPARSE
        set _=%~1
        set __=%1
        shift
        if "%_%"==""                                              goto :E_ARGPARSE
        if "%_%"=="-"   set sep=1&&                               goto :S_ARGPARSE
        if "%_%"=="--"  set sep=2&&                               goto :S_ARGPARSE
        if "%_%"=="---" set sep=3&&                               goto :S_ARGPARSE
        if %sep% equ 0 set /a nargs+=1&& set args[%nargs%]=%__%&& goto :S_ARGPARSE
        if %sep% equ 1 set cmds=%cmds% %__%&&                     goto :S_ARGPARSE
        if %sep% equ 2 set run_opts=%run_opts% %__%&&             goto :S_ARGPARSE
        if %sep% equ 3 set bld_opts=%bld_opts% %__%&&             goto :S_ARGPARSE
    :E_ARGPARSE
    exit /b 0

:f_read_arg
    setlocal
    set i=-1
    :s_loop_f_read_arg
        @REM check range
        set /a i+=1
        if %i% geq %nargs% goto :e_loop_f_read_arg
        @REM check if defined
        set it=!args[%i%]!
        if not defined it goto :s_loop_f_read_arg

        echo %it%| findstr /r "^-[a-zA-Z]*%1[a-zA-Z]*$" >NUL 2>&1 && (
            exit /b 0
        ) || echo %it%| findstr /r "^--%2$" >NUL 2>&1 && (
            exit /b 0
        )

        goto :s_loop_f_read_arg
    :e_loop_f_read_arg
    exit /b 1

:l_print_help
    echo usage: start_dev_container.bat [OPTION]...
    echo                                [- [RUN_COMMAND [ARG]...]]
    echo                                [-- [RUN_OPTION]...]
    echo                                [--- [BUILD_OPTION]...]
    echo.
FOR /F "tokens=2 delims==" %%a IN ('wmic os get OSLanguage /Value') DO set OSLanguage=%%a
if %OSLanguage% equ 1041 goto :l_help_text_ja
    echo Launch the development environment container.
    echo.
    echo -h, --help         Display this help and exit
    echo -   [CMD [ARG]...] docker run ... ^<image^> CMD ARG...
    echo --  [RUN_OPT]...   docker run ... RUN_OPT... ^<image^> ...
    echo --- [BLD_OPT]...   docker build ... BLD_OPT... -t ^<image^> ...
    echo -b, --build        Force build docker image
    echo -B, --build-only   Don't run container, only build
    echo -d, --detach       Run container in background and print container ID
    echo     --disable-itd  Disable default '-itd' options
    echo     --disable-vol  Disable default volume options
    echo -e, --echo         Print build/run command to be executed with arguments
    echo -E, --echo-only    Print build/run command instead of executing it ^(debug^)
    echo -i, --interactive  Keep STDIN open even if not attached
    echo     --no-buildkit  Disable 'DOCKER_BUILDKIT=1' for 'docker build'
    echo     --rm           Automatically remove the container when it exits
    echo -t, --tty          Allocate a pseudo-TTY
    echo -x, --x11          Add options to connect with host's X11 server
    exit /b 0
:l_help_text_ja
    echo 開発環境コンテナを立ち上げます．
    echo.
    echo   -h, --help         このヘルプテキストを表示します
    echo   -   [CMD [ARG]...] docker run ... ^<image^> CMD ARG...
    echo   --  [RUN_OPT]...   docker run ... RUN_OPT... ^<image^> ...
    echo   --- [BLD_OPT]...   docker build ... BLD_OPT... -t ^<image^> ...
    echo   -b, --build        イメージのビルドを強制します
    echo   -B, --build-only   イメージのビルドを強制し，コンテナの起動をスキップします
    echo   -d, --detach       バックグラウンドで実行し新しいコンテナIDを表示します
    echo       --disable-itd  デフォルトで追加される'-itd'オプションを無効化します
    echo       --disable-vol  デフォルトで追加されるボリュームオプションを無効化します
    echo   -e, --echo         実行するコマンドを引数と共に表示します．
    echo   -E, --echo-only    コマンドを実行する代わりに表示します^(デバッグ用^)
    echo   -i, --interactive  コンテナのSTDINにアタッチする
    echo       --no-buildkit  ビルド時の'DOCKER_BUILDKIT=1'を無効化します
    echo       --rm           コンテナの実行後に自動で削除します
    echo   -t, --tty          疑似ターミナル^(pseudo-TTY^)を割り当てます
    echo   -x, --x11          ホストのX11サーバに接続するためのオプションを追加します
    exit /b 0

:: prints the given text and the usage text and exit with code 1.
:: usage:
::     echo error: message
::     goto :l_print_error
:l_print_error
    echo See 'start_dev_container.bat --help'.
    echo.
    echo usage: start_dev_container.bat [OPTION]...
    echo                                [- [RUN_COMMAND [ARG]...]]
    echo                                [-- [RUN_OPTION]...]
    echo                                [--- [BUILD_OPTION]...]
    exit /b 1

:: prints the given text and the usage text and exit with code 127.
:: usage:
::     echo fatal error: message
::     goto :l_print_fatal_error
:l_print_fatal_error
    echo Please contact developer.
    echo Exit.
    exit /b 127
