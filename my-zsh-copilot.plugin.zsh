#!/usr/bin/env zsh

# Default key binding
(( ! ${+ZSH_COPILOT_KEY} )) &&
    typeset -g ZSH_COPILOT_KEY='^z'

# Configuration options
(( ! ${+ZSH_COPILOT_SEND_CONTEXT} )) &&
    typeset -g ZSH_COPILOT_SEND_CONTEXT=true

(( ! ${+ZSH_COPILOT_DEBUG} )) &&
    typeset -g ZSH_COPILOT_DEBUG=false

# Ollama Configuration
(( ! ${+ZSH_COPILOT_OLLAMA_URL} )) &&
    typeset -g ZSH_COPILOT_OLLAMA_URL='http://localhost:11434'

# Choix du modèle Ollama (ex: llama3, codellama, mistral)
(( ! ${+ZSH_COPILOT_OLLAMA_MODEL} )) &&
    typeset -g ZSH_COPILOT_OLLAMA_MODEL='llama3'

# New option to select AI provider
if [[ -z "$ZSH_COPILOT_AI_PROVIDER" ]]; then
    if [[ -n "$OPENAI_API_KEY" ]]; then
        typeset -g ZSH_COPILOT_AI_PROVIDER="openai"
    elif [[ -n "$ANTHROPIC_API_KEY" ]]; then
        typeset -g ZSH_COPILOT_AI_PROVIDER="anthropic"
    else
        # Fallback to Ollama if no keys are present
        typeset -g ZSH_COPILOT_AI_PROVIDER="ollama"
    fi
fi

# System prompt
if [[ -z "$ZSH_COPILOT_SYSTEM_PROMPT" ]]; then
read -r -d '' ZSH_COPILOT_SYSTEM_PROMPT <<- EOM
  You will be given the raw input of a shell command. 
  Your task is to either complete the command or provide a new command that you think the user is trying to type. 
  If you return a completely new command for the user, prefix is with an equal sign (=). 
  If you return a completion for the user's command, prefix it with a plus sign (+). 
  MAKE SURE TO ONLY INCLUDE THE REST OF THE COMPLETION!!! 
  Do not write any leading or trailing characters except if required for the completion to work. 

  Only respond with either a completion or a new command, not both. 
  Your response may only start with either a plus sign or an equal sign.
  Your response MAY NOT start with both! This means that your response IS NOT ALLOWED to start with '+=' or '=+'.

  Your response MAY NOT contain any newlines!
  Do NOT add any additional text, comments, or explanations to your response.
  Do not ask for more information, you won't receive it. 

  Your response will be run in the user's shell. 
  Make sure input is escaped correctly if needed so. 
  Your input should be able to run without any modifications to it.
  DO NOT INTERACT WITH THE USER IN NATURAL LANGUAGE! If you do, you will be banned from the system. 
  Note that the double quote sign is escaped. Keep this in mind when you create quotes. 
  Here are two examples: 
    * User input: 'list files in current directory'; Your response: '=ls' (ls is the builtin command for listing files)
    * User input: 'cd /tm'; Your response: '+p' (/tmp is the standard temp folder on linux and mac).
EOM
fi

if [[ "$ZSH_COPILOT_DEBUG" == 'true' ]]; then
    touch /tmp/zsh-copilot.log
fi

function _fetch_suggestions() {
    local data
    local response
    local message

    if [[ "$ZSH_COPILOT_AI_PROVIDER" == "openai" ]]; then
        # ... (Code OpenAI existant conservé pour compatibilité) ...
        data="{
            \"model\": \"gpt-4o-mini\",
            \"messages\": [
                { \"role\": \"system\", \"content\": \"$full_prompt\" },
                { \"role\": \"user\", \"content\": \"$input\" }
            ]
        }"
        response=$(curl "https://${openai_api_url}/v1/chat/completions" \
            --silent \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $OPENAI_API_KEY" \
            -d "$data")
        response_code=$?

        if [[ "$ZSH_COPILOT_DEBUG" == 'true' ]]; then
            echo "{\"date\":\"$(date)\",\"log\":\"Called OpenAI API\",\"input\":\"$input\",\"response\":\"$response\",\"response_code\":\"$response_code\"}" >> /tmp/zsh-copilot.log
        fi
        
        if [[ $response_code -ne 0 ]]; then
             echo "Error OpenAI." > /tmp/.zsh_copilot_error; return 1
        fi
        message=$(echo "$response" | tr -d '\n' | jq -r '.choices[0].message.content')

    elif [[ "$ZSH_COPILOT_AI_PROVIDER" == "anthropic" ]]; then
        # ... (Code Anthropic existant conservé) ...
        data="{
            \"model\": \"claude-3-5-sonnet-latest\",
            \"max_tokens\": 1000,
            \"system\": \"$full_prompt\",
            \"messages\": [ { \"role\": \"user\", \"content\": \"$input\" } ]
        }"
        response=$(curl "https://${anthropic_api_url}/v1/messages" \
            --silent \
            -H "Content-Type: application/json" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -d "$data")
        response_code=$?

        if [[ "$ZSH_COPILOT_DEBUG" == 'true' ]]; then
            echo "{\"date\":\"$(date)\",\"log\":\"Called Anthropic API\",\"input\":\"$input\",\"response\":\"$response\",\"response_code\":\"$response_code\"}" >> /tmp/zsh-copilot.log
        fi
        
        if [[ $response_code -ne 0 ]]; then
             echo "Error Anthropic." > /tmp/.zsh_copilot_error; return 1
        fi
        message=$(echo "$response" | tr -d '\n' | jq -r '.content[0].text')

    elif [[ "$ZSH_COPILOT_AI_PROVIDER" == "ollama" ]]; then
        # --- BLOC OLLAMA ---
        data="{
            \"model\": \"$ZSH_COPILOT_OLLAMA_MODEL\",
            \"stream\": false,
            \"messages\": [
                { \"role\": \"system\", \"content\": \"$full_prompt\" },
                { \"role\": \"user\", \"content\": \"$input\" }
            ]
        }"
        
        # Note: On utilise /api/chat pour avoir la structure messages system/user
        response=$(curl "${ZSH_COPILOT_OLLAMA_URL}/api/chat" \
            --silent \
            -H "Content-Type: application/json" \
            -d "$data")
        response_code=$?

        if [[ "$ZSH_COPILOT_DEBUG" == 'true' ]]; then
            echo "{\"date\":\"$(date)\",\"log\":\"Called Ollama API\",\"model\":\"$ZSH_COPILOT_OLLAMA_MODEL\",\"input\":\"$input\",\"response\":\"$response\",\"response_code\":\"$response_code\"}" >> /tmp/zsh-copilot.log
        fi

        if [[ $response_code -ne 0 ]]; then
            echo "Error fetching suggestions from Ollama. Check if it's running at $ZSH_COPILOT_OLLAMA_URL" > /tmp/.zsh_copilot_error
            return 1
        fi

        # Extraction pour Ollama
        message=$(echo "$response" | tr -d '\n' | jq -r '.message.content')
    else
        echo "Invalid AI provider selected. Please choose 'openai', 'anthropic' or 'ollama'."
        return 1
    fi

    echo "$message" > /tmp/zsh_copilot_suggestion || return 1
}

function _show_loading_animation() {
    local pid=$1
    local interval=0.1
    local animation_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=1

    cleanup() {
      kill $pid
      echo -ne "\e[?25h"
    }
    trap cleanup SIGINT
    
    while kill -0 $pid 2>/dev/null; do
        zle -R "${animation_chars[i]}"
        i=$(( (i + 1) % ${#animation_chars[@]} ))
        if [[ $i -eq 0 ]]; then i=1; fi
        sleep $interval
    done

    echo -ne "\e[?25h"
    trap - SIGINT
}

function _suggest_ai() {
    #### Prepare environment
    local openai_api_url=${OPENAI_API_URL:-"api.openai.com"}
    local anthropic_api_url=${ANTHROPIC_API_URL:-"api.anthropic.com"}

    local context_info=""
    if [[ "$ZSH_COPILOT_SEND_CONTEXT" == 'true' ]]; then
        local system
        if [[ "$OSTYPE" == "darwin"* ]]; then
            system="Your system is ${$(sw_vers | xargs | sed 's/ /./g')}."
        else 
            system="Your system is ${$(cat /etc/*-release | xargs | sed 's/ /,/g')}."
        fi
        context_info="Context: You are user $(whoami) in directory $(pwd). $system"
    fi

    ##### Get input
    rm -f /tmp/zsh_copilot_suggestion
    local input=$(echo "${BUFFER:0:$CURSOR}" | tr '\n' ';')
    input=$(echo "$input" | sed 's/"/\\"/g')

    _zsh_autosuggest_clear

    # On s'assure que full_prompt est bien échappé pour le JSON
    local full_prompt=$(echo "$ZSH_COPILOT_SYSTEM_PROMPT $context_info" | tr -d '\n' | sed 's/"/\\"/g')

    ##### Fetch message
    read < <(_fetch_suggestions & echo $!)
    local pid=$REPLY

    _show_loading_animation $pid
    
    if [[ ! -f /tmp/zsh_copilot_suggestion ]]; then
        _zsh_autosuggest_clear
        echo $(cat /tmp/.zsh_copilot_error 2>/dev/null || echo "No suggestion available.")
        return 1
    fi

    local message=$(cat /tmp/zsh_copilot_suggestion)

    ##### Process response
    local first_char=${message:0:1}
    local suggestion=${message:1:${#message}}
    
    if [[ "$ZSH_COPILOT_DEBUG" == 'true' ]]; then
        echo "{\"date\":\"$(date)\",\"log\":\"Suggestion extracted.\",\"first_char\":\"$first_char\",\"suggestion\":\"$suggestion\"}" >> /tmp/zsh-copilot.log
    fi

    if [[ "$first_char" == '=' ]]; then
        BUFFER=""
        CURSOR=0
        zle -U "$suggestion"
    elif [[ "$first_char" == '+' ]]; then
        _zsh_autosuggest_suggest "$suggestion"
    fi
}

function zsh-copilot() {
    echo "ZSH Copilot is now active. Press $ZSH_COPILOT_KEY to get suggestions."
    echo ""
    echo "Configurations:"
    echo "    - ZSH_COPILOT_AI_PROVIDER: 'openai', 'anthropic' or 'ollama' (current: $ZSH_COPILOT_AI_PROVIDER)."
    echo "    - ZSH_COPILOT_OLLAMA_URL: URL for Ollama (current: $ZSH_COPILOT_OLLAMA_URL)."
    echo "    - ZSH_COPILOT_OLLAMA_MODEL: Model for Ollama (current: $ZSH_COPILOT_OLLAMA_MODEL)."
}

zle -N _suggest_ai
bindkey "$ZSH_COPILOT_KEY" _suggest_ai
