@echo off
setlocal enabledelayedexpansion

REM MIT License
REM 
REM Copyright (c) 2020 Takumi Kodama
REM 
REM Permission is hereby granted, free of charge, to any person obtaining a copy
REM of this software and associated documentation files (the "Software"), to deal
REM in the Software without restriction, including without limitation the rights
REM to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
REM copies of the Software, and to permit persons to whom the Software is
REM furnished to do so, subject to the following conditions:
REM 
REM The above copyright notice and this permission notice shall be included in all
REM copies or substantial portions of the Software.
REM 
REM THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
REM IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
REM FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
REM AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
REM LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
REM OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
REM SOFTWARE.

REM ############################################################################
REM                                                                           ##
REM Development Container start up script for Windows                         ##
REM                                                                           ##
REM ############################################################################
call :f_read_config image_tag
call :f_read_config build_trg
call :f_read_config build_ctx
call :f_read_config volumes true
call :f_read_config run_cmd

@REM separate all arguments into args, cmds, run_opts, bld_opts
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

@REM @param %1 parameter/variable name to read/store
@REM @param %2 true if the paramer is array
:f_read_config
    @REM check parameter/variable name
    if "%1"=="" exit /b 127
    @REM calculates the length to be cut from the lines read from the file
    call :f_strlen %1 f_read_config_cutlen
    set /a f_read_config_cutlen+=1
    @REM index of the array
    set f_read_config_j=0
    for /f "usebackq" %%A in (`findstr /r "^%1%=.*" start_dev_container.cfg`) do (
        set f_read_config_tmp=%%A
        set f_read_config_tmp=!f_read_config_tmp:~%f_read_config_cutlen%!
        if "%2"=="true" (
            set %1[!f_read_config_j!]=!f_read_config_tmp!
        ) else (
            set %1=!f_read_config_tmp!
        )
        set /a f_read_config_j+=1
    )
    exit /b 0

@REM Check string length of the first argument.
@REM If the second argument is given as a variable name, the length will be stored into the variable.
@REM Otherwise, it will be stored into %f_strlen_return%
@REM @param %1 string to be checked
@REM @param %2 variable name for storing the result (option)
@REM @return 0
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

:l_print_error
    echo See 'start_dev_container.bat --help'.
    echo.
    echo usage: start_dev_container.bat [OPTION]...
    echo                                [- [RUN_COMMAND [ARG]...]]
    echo                                [-- [RUN_OPTION]...]
    echo                                [--- [BUILD_OPTION]...]
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
    echo �J�����R���e�i�𗧂��グ�܂��D
    echo.
    echo -h, --help         ���̃w���v�e�L�X�g��\�����܂�
    echo -   [CMD [ARG]...] docker run ... ^<image^> CMD ARG...
    echo --  [RUN_OPT]...   docker run ... RUN_OPT... ^<image^> ...
    echo --- [BLD_OPT]...   docker build ... BLD_OPT... -t ^<image^> ...
    echo -b, --build        �C���[�W�̃r���h���������܂�
    echo -B, --build-only   �C���[�W�̃r���h���������C�R���e�i�̋N�����X�L�b�v���܂�
    echo -d, --detach       �o�b�N�O���E���h�Ŏ��s���V�����R���e�iID��\�����܂�
    echo     --disable-itd  �f�t�H���g�Œǉ������'-itd'�I�v�V�����𖳌������܂�
    echo     --disable-vol  �f�t�H���g�Œǉ������{�����[���I�v�V�����𖳌������܂�
    echo -e, --echo         ���s����R�}���h�������Ƌ��ɕ\�����܂��D
    echo -E, --echo-only    �R�}���h�����s�������ɕ\�����܂�^(�f�o�b�O�p^)
    echo -i, --interactive  �R���e�i��STDIN�ɃA�^�b�`����
    echo     --no-buildkit  �r���h����'DOCKER_BUILDKIT=1'�𖳌������܂�
    echo     --rm           �R���e�i�̎��s��Ɏ����ō폜���܂�
    echo -t, --tty          �^���^�[�~�i��^(pseudo-TTY^)�����蓖�Ă܂�
    echo -x, --x11          �z�X�g��X11�T�[�o�ɐڑ����邽�߂̃I�v�V������ǉ����܂�
    exit /b 0
