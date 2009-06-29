"=============================================================================
" FILE: bg.vim
" AUTHOR: Shougo Matsushita <Shougo.Matsu@gmail.com>
" Last Modified: 26 Jun 2009
" Usage: Just source this file.
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
" Version: 1.8, for Vim 7.0
"-----------------------------------------------------------------------------
" ChangeLog: "{{{
"   1.8: Supported pipe.
"
"   1.7: Improved error catch.
"     - Get status. 
"
"   1.6: Use interactive.
"
"   1.5: Improved autocmd.
"
"   1.4: Split nicely.
"
"   1.3:
"     - Use g:VimShell_EnableInteractive option.
"     - Use utls/process.vim.
"
"   1.2:
"     - Use vimproc.
"
"   1.1:
"     - Fixed in *nix.
"
"   1.0:
"     - Initial version.
""}}}
"-----------------------------------------------------------------------------
" TODO: "{{{
"     - Nothing.
""}}}
" Bugs"{{{
"     -
""}}}
"=============================================================================

let s:background_programs = 0
augroup vimshell_bg
    autocmd!
augroup END

function! vimshell#internal#bg#execute(program, args, fd, other_info)"{{{
    " Execute program in background.

    if empty(a:args)
        return 
    elseif a:args[0] == 'shell'
        " Background shell.
        if has('win32') || has('win64')
            if g:VimShell_UseCkw
                " Use ckw.
                silent execute printf('!start ckw -e %s', &shell)
            else
                silent execute printf('!start %s', &shell)
            endif
        elseif &term =~ '^screen'
            silent execute printf('!screen %s', &shell)
        else
            " Can't Background execute.
            shell
        endif
    elseif a:args[0] == 'iexe'
        " Background iexe.
        let l:other_info = a:other_info
        let l:other_info.is_background = 1
        return vimshell#internal#iexe#execute(a:args[0], a:args[1:], a:fd, l:other_info)
    elseif g:VimShell_EnableInteractive
        " Background execute.
        return s:init_bg(a:fd, a:args, a:other_info.is_interactive)
    else
        " Execute in screen.
        let l:other_info = a:other_info
        return vimshell#internal#screen#execute(a:args[0], a:args[1:], a:fd, l:other_info)
    endif
endfunction"}}}

function! vimshell#internal#bg#vimshell_bg(args)"{{{
    call vimshell#internal#bg#execute('bg', a:args, {'stdin' : '', 'stdout' : '', 'stderr' : ''}, {'is_interactive' : 0, 'is_background' : 1})
endfunction"}}}

function! s:init_bg(fd, args, is_interactive)"{{{
    if exists('b:vimproc_sub')
        " Delete zombee process.
        call interactive#exit()
    endif

    " Initialize.
    let l:proc = proc#import()
    let l:sub = []

    " Search pipe.
    let l:commands = [[]]
    for arg in a:args
        if arg == '|'
            call add(l:commands, [])
        else
            call add(l:commands[-1], arg)
        endif
    endfor

    for command in l:commands
        try
            if has('win32') || has('win64')
                call add(l:sub, l:proc.popen3(command))
            else
                call add(l:sub, l:proc.ptyopen(command))
            endif
        catch 'list index out of range'
            if empty(command)
                let l:error = 'Wrong pipe used.'
            else
                let l:error = printf('File: "%s" is not found.', command[0])
            endif

            if a:is_interactive
                call vimshell#error_line(a:fd, l:error)
            else
                echohl WarningMsg | echo l:error | echohl None
            endif

            return 0
        endtry
    endfor

    " Init buffer.
    if a:is_interactive
        call vimshell#print_prompt()
    endif
    " Split nicely.
    if winheight(0) > &winheight
        split
    else
        vsplit
    endif
    edit `=join(a:args).'&'.(bufnr('$')+1)`
    setlocal buftype=nofile
    setlocal noswapfile

    " Set variables.
    let b:vimproc = l:proc
    let b:vimproc_sub = l:sub
    let b:vimproc_fd = a:fd

    " Input from stdin.
    if b:vimproc_fd.stdin != ''
        if has('win32') || has('win64')
            call b:vimproc_sub[0].stdin.write(vimshell#read(a:fd))
            call b:vimproc_sub[0].stdin.close()
        else
            call b:vimproc_sub[0].write(vimshell#read(a:fd))
        endif
    endif

    if s:background_programs <= 0
        autocmd vimshell_bg CursorHold * call s:check_bg()
    endif
    let s:background_programs += 1
    autocmd vimshell_bg BufDelete <buffer>       call s:on_exit()
    nnoremap <buffer><silent><C-c>       :<C-u>call <sid>on_exit()<CR>
    inoremap <buffer><silent><C-c>       <ESC>:<C-u>call <sid>on_exit()<CR>
    nnoremap <buffer><silent><CR>       :<C-u>call interactive#execute_out()<CR>

    call interactive#execute_out()

    return 1
endfunction"}}}

function! s:on_exit()
    let s:background_programs -= 1

    augroup vimshell_bg
        autocmd! * <buffer>
    augroup END

    if s:background_programs <= 0
        autocmd! vimshell_bg CursorHold
    endif

    call interactive#exit()

    if exists('b:vimshell_system_variables')
        let b:vimshell_system_variables['status'] = b:vimproc_status
    endif
endfunction

function! s:check_bg()"{{{
    let l:save_cursor = getpos('.')
    let l:bufnumber = 1
    let l:current_buf = bufnr('%')
    while l:bufnumber <= bufnr('$')
        if buflisted(l:bufnumber) && string(getbufvar(l:bufnumber, 'sub')) != ''
            execute 'buffer ' . l:bufnumber
            call interactive#execute_out()
        endif
        let l:bufnumber += 1
    endwhile
    execute 'buffer ' . l:current_buf
    call setpos('.', l:save_cursor)
endfunction"}}}
