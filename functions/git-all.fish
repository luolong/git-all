function git-all --wraps=git --description 'execute same git command on all repos inside this directory'
  # without arguments, just show git help and exit early
  count $argv > /dev/null; or begin git help; return; end

  # show help and exit early
  if contains -- '--help' $argv
    git $argv
    return
  end

  # parse git main args (so we can detect main git command)
  argparse -n 'git-all' -i -s \
    'version' 'h/help' 'C=' \
    'git-dir=' 'work-tree=' 'namespace=' 'super-prefix=' \
    'bare' \
    'list-cmds=' \
    'verbose' -- $argv

  # Exit early for some flags
  test -n "$_flag_version"; and begin git --version; return; end
  
  # These don't make much sense in git-all context, so we error out on these
  test -n "$_flag_C"; and begin 
    __ERROR "'-C' is not supported for git-all!" \
            "Did you mean:" \
            "" \
            (printf "  %s" (string escape -- git -C $_flag_C $argv | string join ' ')) >&2
    return 1;
  end
  test -n "$_flag_git_dir"; and begin __ERROR "'--git-dir' is not supported for git-all"; return 1; end
  test -n "$_flag_work_tree"; and begin __ERROR "'--work-tree' is not supported for git-all"; return 1; end
  test -n "$_flag_namespace"; and begin __ERROR "'--namespace' is not supported for git-all"; return 1; end
  test -n "$_flag_super_prefix"; and begin __ERROR "'--super-prefix' is not supported for git-all"; return 1; end
  test -n "$_flag_bare"; and begin __ERROR "'--bare' is not supported for git-all"; return 1; end
  
  if test -n "$_flag_verbose"
    set_color -d
    echo "Displaying verbose output" >&2
    set_color normal
  else
    set -l __git_command $argv[1]
    switch "$__git_command"
      case status
        __git_all_status $argv[2..-1]
        return $status
      
      case '*'
        set_color -d
        echo "No pretty rendering for 'git $__git_command'. Falling back to verbose output" >&2
        set_color normal
    end
  end
  
  # Go over all the repos in this folder and issue the command ith re repository context
  for repo in (ein tools find)
    __git_all_apply $repo $argv
  end
  
end

function __ERROR -a 'message'
  echo (set_color -o red)"ERROR:"(set_color normal) (set_color brred)$message(set_color normal) >&2
  if test (count $argv) -gt 1
    for m in $argv[2..]
      echo $m >&2
    end
  end
  return 1;
end


function __git_all_apply
  set -f colorize true
  if test -t 1
    set -l ncolors (tput colors)
    if test -z "$ncolors"; or test $ncolors -lt 8
      set colorize false
    end
  end
  
  if $colorize; set_color -o green; end
  echo -n '==> '
  if $colorize; set_color white; end
  echo -n git -C $argv
  if $colorize; set_color normal; end
  echo
  
  git -C $argv
end

function __git_all_status

  set -fa __status 'STATUS'
  set -fa __status_path 'REPOSITORY'
  set -fa __status_head 'HEAD'
  set -fa __status_upstream 'UPSTREAM'
  set -fa __status_ab 'A/B'
  set -fa __status_ahead 'A'
  set -fa __status_behind 'B'
  set -fa __status_modified 'M'
  set -fa __status_uncommitted 'S'
  set -fa __status_conflict 'C'
  set -fa __status_untracked 'U'
  
  for __repo in (ein tools find)

    set -l __repo_head ""
    set -l __repo_remote ""
    set -l __repo_ab ""
    set -l __repo_ahead 0
    set -l __repo_behind 0
    set -l __repo_modified 0
    set -l __repo_conflict 0
    set -l __repo_uncommitted 0
    set -l __repo_untracked 0
    
    git -C $__repo status --porcelain=v2 --branch --untracked-files --ignored=no | while read -l line
      switch "$line"
        case "# branch.oid *"
        case "# branch.head *"
          set __repo_head (string sub --start 15 "$line")
        case "# branch.upstream *"
          set __repo_upstream (string sub --start 19 "$line")
        case "# branch.ab *"
          set __repo_ab (string sub --start 13 "$line")
          set -l __ab (string split ' ' $__repo_ab)
          set __repo_ahead (math abs $__ab[1])
          set __repo_behind (math abs $__ab[2])
        case '\? *'
          set __repo_untracked (math $__repo_untracked + 1)
        case '*'
          set -l __change (string split -f 1,2 ' '  "$line")
          switch $__change[1]
           case 'u'
              echo "unmerged changes: $line"
              test "$__change[2]" == 'UU'; and set __repo_conflict (math $__repo_conflict + 1)
           case '1'
              set -l __xy (string split '' "$__change[2]")
              test $__xy[1] != .; and set __repo_uncommitted (math $__repo_uncommitted + 1)
              test $__xy[2] != .; and set __repo_modified (math $__repo_modified + 1)
            case '2'
              set -l __xy (string split '' $__change[2])
          end
      end
    end
  
    set -l __repo_status "clean"
    if test $__repo_conflict -gt 0
      set __repo_status 'conflict'
    else if test $__repo_modified -gt 0
      set __repo_status 'modified'
    else if test $__repo_uncommitted -gt 0
      set __repo_status 'uncommitted'
    else if test $__repo_untracked -gt 0
      set __repo_status 'dirty'
    else if test (math $__repo_ahead + $__repo_behind) -gt 0
      if test $__repo_behind -eq 0
        set __repo_status 'ahead'
      else if test $__repo_ahead -eq 0
        set __repo_status 'behind'
      else
        set __repo_status 'out of sync'
      end
    end
    
    if test "$__repo" = "."
      set __repo ../(basename $PWD)
    end
    
    set -fa __status $__repo_status
    set -fa __status_path $__repo
    set -fa __status_head $__repo_head
    set -fa __status_upstream $__repo_upstream
    set -fa __status_ab $__repo_ab
    set -fa __status_ahead "$__repo_ahead"
    set -fa __status_behind "$__repo_behind"
    set -fa __status_modified $__repo_modified
    set -fa __status_uncommitted $__repo_uncommitted
    set -fa __status_conflict $__repo_conflict
    set -fa __status_untracked $__repo_untracked
  end

  set -l __status_length (math max (string join \n $__status | string length | string join ',' ))
  set -l __path_length (math max (string join \n $__status_path | string length | string join ','))
  set -l __head_length (math max (string join \n $__status_head | string length | string join ','))
  set -l __upstream_length (math max (string join \n $__status_upstream | string length | string join ','))
  set -l __ahead_length (math max (string join \n $__status_ahead | string length | string join ',' ))
  set -l __behind_length (math max (string join \n $__status_behind | string length | string join ',' ))
  
  set -l __total_ahead (math (string join ' + ' $__status_ahead[2..-1]))
  set -l __width_ahead (math max (string length $__status_ahead | string join ','))
  if test $__total_ahead -gt 0; set __width_ahead (math $__width_ahead + 1); end
  
  set -l __total_behind (math (string join ' + ' $__status_behind[2..-1]))
  set -l __width_behind (math max (string length $__status_behind | string join ','))
  if test $__total_behind -gt 0; set __width_behind (math $__width_behind + 1); end

  set -l __total_ab (math $__total_ahead + $__total_behind)
  
  set -l __total_modified (math (string join ' + ' $__status_modified[2..-1]))
  set -l __width_modified (math max (string join \n $__status_modified | string length | string join ','))
  
  set -l __total_uncommitted (math (string join ' + ' $__status_uncommitted[2..-1]))
  set -l __width_uncommitted (math max (string join \n $__status_uncommitted | string length | string join ','))
  
  set -l __total_conflict (math (string join ' + ' $__status_conflict[2..-1]))

  set -l __total_untracked (math (string join ' + ' $__status_untracked[2..-1]))
  set -l __width_untracked (math max (string join \n $__status_untracked | string length | string join ','))
  
  set -l __padding 2
  for i in (seq (count $__status_path)) 
    if test $i -eq 1
      set_color -o white
    end
    
    echo -n (string pad --right -w (math $__padding + $__path_length) $__status_path[$i])
    echo -n (string pad --right -w (math $__padding + $__status_length) (__git_all_status_status "$__status[$i]"))
    echo -n (string pad --right -w (math $__padding + $__head_length) $__status_head[$i])
    echo -n (string pad --right -w (math $__padding + $__upstream_length) $__status_upstream[$i])

    if test $__total_ab -gt 0
      set -l __ahead $__status_ahead[$i]
      set -l __behind $__status_behind[$i]
      
      if test $__ahead = "A"
        echo -n (string pad -w $__width_ahead $__ahead)
      else if test $__ahead -eq 0
        set_color -d brblack
        echo -n (string pad -w $__width_ahead '-')
        if test $__behind -gt 0
          set_color normal
        end
      else
        set_color green
        echo -n (string pad -w $__width_ahead "+$__ahead")
        set_color normal
      end
      
      echo -n '/'
      
      if test "$__behind" = "B"
        echo -n (string pad -w $__width_behind --right $__behind)
      else if test $__behind -eq 0
        if test $__ahead -gt 0
          set_color -d brblack
        end
        echo -n (string pad -w $__width_behind --right '-')
        set_color normal
      else
        set_color red
        echo -n (string pad -w $__width_behind --right "x$__behind" | string replace 'x' '-')
        set_color normal
      end
    end
    
    if test $__total_modified -gt 0
      if test $i -eq 1
        echo -n (string pad -w (math $__padding + $__width_modified) $__status_modified[$i])
      else if test $__status_modified[$i] -eq 0
        set_color -d brblack
        echo -n (string pad -w (math $__padding + $__width_modified) $__status_modified[$i])
        set_color normal
      else
        set_color red
        echo -n (string pad -w (math $__padding + $__width_modified) $__status_modified[$i])
        set_color normal
      end
    end

    if test $__total_uncommitted -gt 0
      if test $i -eq 1
        echo -n (string pad -w (math $__padding + $__width_uncommitted) $__status_uncommitted[$i])
      else if test $__status_uncommitted[$i] -eq 0
        set_color -d brblack
        echo -n (string pad -w (math $__padding + $__width_uncommitted) $__status_uncommitted[$i])
        set_color normal
      else
        set_color red
        echo -n (string pad -w (math $__padding + $__width_uncommitted) $__status_uncommitted[$i])
        set_color normal
      end
    end

    if test $__total_untracked -gt 0
      if test $i -eq 1
        echo -n (string pad -w (math $__padding + $__width_untracked) $__status_untracked[$i])
      else if test $__status_untracked[$i] -eq 0
        set_color -d brblack
        echo -n (string pad -w (math $__padding + $__width_untracked) $__status_untracked[$i])
        set_color normal
      else
        set_color red
        echo -n (string pad -w (math $__padding + $__width_untracked) $__status_untracked[$i])
        set_color normal
      end
    end

    echo
    set_color normal
  end
  
  set -l __total_changes (math $__total_ab + $__total_modified + $__total_uncommitted + $__total_conflict + $__total_untracked)
  if test $__total_changes -gt 0

    echo
    set_color -o white
    echo Legend:
    set_color normal
    set -l __indent '  '

    if test $__total_ab -gt 0
      test $__total_ahead -gt 0; and set -la __legend_label (__git_all_status_status "ahead")
      test $__total_behind -gt 0; and set -la __legend_label (__git_all_status_status "behind")
      test $__total_ahead -gt 0 -a $__total_behind -gt 0; and set -la __legend_label (__git_all_status_status "out of sync")

      echo $__indent(string join '/' $__legend_label):
      echo -n "$__indent$__indent"(set_color -o white)"$__status_ab[1]"
      set_color -d -i white
      echo -n \t- Number of commits ahead/behind the remote.
      set_color normal
      echo
    end

    if test (math $__total_modified + $__total_uncommitted + $__total_conflict) -gt 0
      test $__total_modified -gt 0; and set -la __legend_label (__git_all_status_status "modified")
      test $__total_uncommitted -gt 0; and set -la __legend_label (__git_all_status_status "uncommitted")
      test $__total_conflict -gt 0; and set -la __legend_label (__git_all_status_status "conflict")

      echo $__indent(string join '/' $__legend_label)
      test $__total_modified -gt 0
      and echo -e "$__indent$__indent"(set_color -o white)"$__status_modified[1]"(set_color -d -i white)"\t- Number of modified files in the working tree not staged for commit"(set_color normal)

      test $__total_uncommitted -gt 0
      and echo -e "$__indent$__indent"(set_color -o white)"$__status_uncommitted[1]"(set_color -d -i white)"\t- Number of uncommited files staged for commit"(set_color normal)
    end

    if test $__total_untracked -gt 0
      echo $__indent(__git_all_status_status 'dirty'):
      echo -e "$__indent$__indent"(set_color -o white)"$__status_untracked[1]"(set_color -d -i white)"\t- Number of files in the working tree not tracked by Git"(set_color normal)
    end

    set -l __total_untracked (math (string join ' + ' $__status_untracked[2..-1]))
    set -l __width_untracked (math max (string join \n $__status_untracked | string length | string join ','))
    set_color normal
  end
end

function __git_all_status_status -a __status
  set -l __color
  switch $__status
    case 'clean'
      set __color green
    case 'conflict'
      set __color yellow
    case 'modified'
      set __color red
    case 'uncommitted'
      set __color yellow
    case 'dirty'
      set __color '-i' '-u' brblack 
    case 'ahead'
      set __color '-u' brgreen
    case 'behind'
      set __color '-i' bryellow
    case 'out of sync'
      set __color '-i' brred
  end
  
  if test -n "$__color"; set_color $__color; end
  echo -n $__status
  if test -n "$__color"; set_color normal; end
  echo
end

