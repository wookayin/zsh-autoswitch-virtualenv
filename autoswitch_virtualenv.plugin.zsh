export AUTOSWITCH_VERSION='1.8.0'

local RED="\e[31m"
local GREEN="\e[32m"
local PURPLE="\e[35m"
local CYAN="\e[36m"
local BOLD="\e[1m"
local NORMAL="\e[0m"


if (! type "virtualenv" > /dev/null) && (! type "conda" > /dev/null); then
    export DISABLE_AUTOSWITCH_VENV="1"
    printf "${BOLD}${RED}"
    printf "zsh-autoswitch-virtualenv requires virtualenv or conda to be installed!\n\n"
    printf "${NORMAL}"
    printf "If this is already installed but you are still seeing this message, \n"
    printf "then make sure the ${BOLD}virtualenv${NORMAL} command is in your PATH.\n"
    printf "\n"
fi


function _virtual_env_dir() {
    local VIRTUAL_ENV_DIR="${AUTOSWITCH_VIRTUAL_ENV_DIR:-$HOME/.virtualenvs}"
    mkdir -p "$VIRTUAL_ENV_DIR"
    printf "%s" "$VIRTUAL_ENV_DIR"
}


function _python_version() {
    local PYTHON_BIN="$1"
    if [[ -f "$PYTHON_BIN" ]] then
        # For some reason python --version writes to stderr
        printf "%s" "$($PYTHON_BIN --version 2>&1)"
    else
        printf "unknown ($PYTHON_BIN)"
    fi
}

function _maybeworkon() {
    local venv_name="$1"
    local venv_type="$2"
    local venv_dir
    local py_bin

    local DEFAULT_MESSAGE_FORMAT="Switching %venv_type: ${BOLD}${PURPLE}%venv_name${NORMAL} ${GREEN}[🐍%py_version]${NORMAL} ${CYAN}%py_bin${NORMAL}"
    if [[ "$LANG" != *".UTF-8" ]]; then
        # Remove multibyte characters if the terminal does not support utf-8
        DEFAULT_MESSAGE_FORMAT="${DEFAULT_MESSAGE_FORMAT/🐍/}"
    fi

    local venv_current=""
    if [[ "$venv_type" != "conda" ]]; then
        [[ -n "$VIRTUAL_ENV" ]] && venv_current="$(basename $VIRTUAL_ENV)"
    else
      venv_current="$CONDA_DEFAULT_ENV"
    fi

    if [[ "$venv_name" != "$venv_current" ]]; then
        local venv_activated=''
        # try activating the environment first.
        if [[ "$venv_type" != "conda" ]]; then
          # Much faster to source the activate file directly rather than use the `workon` command
          source "$venv_dir/bin/activate" && venv_activated=1 || \
              true;  # the plugin.zsh should not return false upon init
        else
          [[ -n "$CONDA_DEFAULT_ENV" ]] && conda deactivate;
          conda activate "$venv_name" && venv_activated=1 || \
              true;  # the plugin.zsh should not return false upon init
        fi

        # Print some messages
        if [ -n "$venv_activated" ] && [ -z "$AUTOSWITCH_SILENT" ]; then
            py_bin="$(which python)"
            local py_version="$(_python_version "$py_bin")"

            local message="${AUTOSWITCH_MESSAGE_FORMAT:-"$DEFAULT_MESSAGE_FORMAT"}"
            message="${message//\%venv_type/$venv_type}"
            message="${message//\%venv_name/$venv_name}"
            message="${message//\%py_version/$py_version}"
            message="${message//\%py_bin/$py_bin}"
            printf "${message}\n"
        fi
    fi
}

# Gives the path to the nearest parent .venv or .condaenv file or nothing if it gets to root
function _check_venv_path()
{
    local check_dir="$1"

    if [[ -f "${check_dir}/.condaenv" ]]; then
        printf "${check_dir}/.condaenv"
        return
    elif [[ -f "${check_dir}/.venv" ]]; then
        printf "${check_dir}/.venv"
        return
    elif [[ -f "${check_dir}/.venv/bin/python" ]]; then
        printf "${check_dir}/.venv"
        return
    else
        if [ "$check_dir" = "/" ]; then
            return
        fi
        _check_venv_path "$(dirname "$check_dir")"
    fi
}


# Automatically switch virtualenv when .venv file detected
function check_venv()
{
    local SWITCH_TO=""
    local VIRTUALENV_DIR=""

    # Get the .venv file, scanning parent directories
    venv_path=$(_check_venv_path "$PWD")

    if [[ -n "$venv_path" ]]; then
        # resolve symbolic link because symlinks have 777 permissions
        venv_path=$(readlink -f "$venv_path")

        stat --version &> /dev/null
        if [[ $? -eq 0 ]]; then   # Linux, or GNU stat
            file_owner="$(stat -c %u "$venv_path")"
            file_permissions="$(stat -c %a "$venv_path")"
        else                      # macOS, or FreeBSD stat
            file_owner="$(stat -f %u "$venv_path")"
            file_permissions="$(stat -f %OLp "$venv_path")"
        fi

        if [[ "$file_owner" != "$(id -u)" ]]; then
            printf "AUTOSWITCH WARNING: Virtualenv will not be activated\n\n"
            printf "Reason: Found a .venv file but it is not owned by the current user\n"
            printf "Change ownership of ${PURPLE}$venv_path${NORMAL} to ${PURPLE}'$USER'${NORMAL} to fix this\n"
        elif [[ -f "$venv_path" ]] && ! [[ "$file_permissions" =~ ^[64][04][04]$ ]]; then
            printf "AUTOSWITCH WARNING: Virtualenv will not be activated\n\n"
            printf "Reason: Found a .venv file with weak permission settings ($file_permissions).\n"
            printf "Run the following command to fix this: ${PURPLE}\"chmod 600 $venv_path\"${NORMAL}\n"
        else
            if [[ -d "$venv_path" ]]; then
                VIRTUALENV_DIR="$venv_path"
            else
                # Read $venv_path (.condaenv, .venv). Exclude comments with prefix '#'
                SWITCH_TO="$(/bin/cat "$venv_path" | grep -v '^#' | head -n1)"
            fi
        fi
    elif [[ -f "$PWD/requirements.txt" || -f "$PWD/setup.py" ]]; then
        printf "Python project detected. "
        printf "Run ${PURPLE}mkvenv${NORMAL} to setup autoswitching\n"
    fi

    if [[ -n "$VIRTUALENV_DIR" ]]; then
        source "$VIRTUALENV_DIR/bin/activate" || \
            true;
    elif [[ -n "$SWITCH_TO" ]]; then
        if [[ "$venv_path" == *".condaenv" ]]; then
          venv_type="conda"
        else
          venv_type="virtualenv"
        fi
        _maybeworkon "$SWITCH_TO" "$venv_type"

        # check if Pipfile exists rather than invoking pipenv as it is slow
    elif [[ -a "Pipfile" ]] && type "pipenv" > /dev/null; then
        venv_path="$(PIPENV_IGNORE_VIRTUALENVS=1 pipenv --venv)"
        _maybeworkon "$(basename "$venv_path")" "pipenv"
    else
        # Do not deactivate outside a project
        #_default_venv
    fi
}

# Switch to the default virtual environment
function _default_venv()
{
    if [[ -n "$AUTOSWITCH_DEFAULTENV" ]]; then
        _maybeworkon "$AUTOSWITCH_DEFAULTENV" "virtualenv"
    elif [[ -n "$VIRTUAL_ENV" ]]; then
        deactivate
    elif [[ -n "$CONDA_DEFAULT_ENV" ]]; then
        source deactivate
    fi
}


# remove virtual environment for current directory
function rmvenv()
{
    if [[ -f ".venv" ]]; then

        venv_name="$(<.venv)"

        # detect if we need to switch virtualenv first
        if [[ -n "$VIRTUAL_ENV" ]]; then
            current_venv="$(basename $VIRTUAL_ENV)"
            if [[ "$current_venv" = "$venv_name" ]]; then
                _default_venv
            fi
        fi

        printf "Removing ${PURPLE}%s${NORMAL}...\n" "$venv_name"
        rm -rf "$(_virtual_env_dir)/$venv_name"
        rm ".venv"
    else
        printf "No .venv file in the current directory!\n"
    fi
}


# helper function to create a virtual environment for the current directory
function mkvenv()
{
    if [[ -d ".venv" || -f ".venv" ]]; then
        printf ".venv already exists. If this is a mistake use the rmvenv command\n"
    else
        venv_name="$(basename $PWD)"

        printf "Creating ${PURPLE}%s${NORMAL} virtualenv\n" "$venv_name"

        # Copy parameters variable so that we can mutate it
        params=("${@[@]}")

        if [[ -n "$AUTOSWITCH_DEFAULT_PYTHON" && ${params[(I)--python*]} -eq 0 ]]; then
            params+="--python=$AUTOSWITCH_DEFAULT_PYTHON"
        fi

        local venv_path
        if [[ ${params[(I).venv]} -ne 0 ]]; then
          venv_path=".venv"
          unset params[${params[(I).venv]}]
        else
          venv_path="$(_virtual_env_dir)/$venv_name"
        fi

        if [[ ${params[(I)--verbose]} -eq 0 ]]; then
            virtualenv $params "$venv_path"
        else
            virtualenv $params "$venv_path" > /dev/null
        fi

        if [[ "$?" != 0 ]]; then
          printf "ERROR: Failed to create an virtualenv. Try again with --verbose"
          return 1;
        fi

        if [[ ! -d ".venv" ]]; then
          printf "$venv_name\n" > ".venv"
          chmod 600 .venv
          _maybeworkon "$venv_name"
        else
          _maybeworkon "$(pwd)/.venv"
        fi

        install_requirements
    fi
}


function install_requirements() {
    if [[ -f "$AUTOSWITCH_DEFAULT_REQUIREMENTS" ]]; then
        printf "Install default requirements? (${PURPLE}$AUTOSWITCH_DEFAULT_REQUIREMENTS${NORMAL}) [y/N]: "
        read ans

        if [[ "$ans" = "y" || "$ans" == "Y" ]]; then
            pip install -r "$AUTOSWITCH_DEFAULT_REQUIREMENTS"
        fi
    fi

    if [[ -f "$PWD/setup.py" ]]; then
        printf "Found a ${PURPLE}setup.py${NORMAL} file. Install dependencies? [y/N]: "
        read ans

        if [[ "$ans" = "y" || "$ans" = "Y" ]]; then
            pip install .
        fi
    fi

    setopt nullglob
    for requirements in *requirements.txt
    do
        printf "Found a ${PURPLE}%s${NORMAL} file. Install? [y/N]: " "$requirements"
        read ans

        if [[ "$ans" = "y" || "$ans" = "Y" ]]; then
            pip install -r "$requirements"
        fi
    done
}


function enable_autoswitch_virtualenv() {
    autoload -Uz add-zsh-hook
    disable_autoswitch_virtualenv
    add-zsh-hook chpwd check_venv
}


function disable_autoswitch_virtualenv() {
    add-zsh-hook -D chpwd check_venv
}


if [[ -z "$DISABLE_AUTOSWITCH_VENV" ]]; then
    enable_autoswitch_virtualenv
    check_venv
fi
# vim: set ts=4 sts=4 sw=4:
