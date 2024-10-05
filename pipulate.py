import asyncio
import json
import re
from dataclasses import dataclass
from typing import Callable, Awaitable

import requests
from starlette.concurrency import run_in_threadpool

from fasthtml.common import *

from todo_app import todos, Todo, mk_input as todo_mk_input

# Configuration and Constants
MAX_LLM_RESPONSE_WORDS = 40
SEARCH_WIDTH = "140px"
ACTIONS_WIDTH = "120px"
CHAT_INTERFACE_WIDTH = "150px"
LOGO_WIDTH = "100px"

# Styles
MATRIX_STYLE = (
    "color: #00ff00; text-shadow: 0 0 5px #00ff00; "
    "font-family: 'Courier New', monospace;"
)
USER_STYLE = (
    "color: #ffff00; text-shadow: 0 0 5px #ffff00; "
    "font-family: 'Courier New', monospace;"
)

# Initialize conversation
conversation = [
    {
        "role": "system",
        "content": "You are a Todo App with attitude. Be sassy but helpful.",
    },
]

# Active users connected via WebSocket
users = {}


@dataclass
class Chatter:
    send: Callable[[str], Awaitable[None]]
    update: Callable[[str], Awaitable[None]]
    finish: Callable[[], Awaitable[None]]


@dataclass
class SimpleChatter:
    send: Callable[[str], Awaitable[None]]


def limit_llm_response(response: str) -> str:
    """Limit the LLM response to a maximum number of words."""
    words = response.split()
    return ' '.join(words[:MAX_LLM_RESPONSE_WORDS])


def parse_version(version_string):
    """Parse a version string into a list of integers and strings for comparison."""
    return [int(x) if x.isdigit() else x for x in re.findall(r'\d+|\D+', version_string)]


def get_best_llama_model(models):
    """Select the best available LLaMA model from the list of models."""
    llama_models = [model for model in models if model.lower().startswith('llama')]
    if not llama_models:
        return None

    def key_func(model):
        parts = model.split(':')
        base_name = parts[0]
        version = parts[1] if len(parts) > 1 else ''
        base_version = re.search(r'llama(\d+(?:\.\d+)*)', base_name.lower())
        base_version = base_version.group(1) if base_version else '0'
        return (
            parse_version(base_version),
            1 if version == 'latest' else 0,
            parse_version(version),
        )

    return max(llama_models, key=key_func)


def get_available_models():
    """Retrieve the list of available models from the Ollama API."""
    try:
        response = requests.get("http://localhost:11434/api/tags", timeout=10)
        response.raise_for_status()
        return [model['name'] for model in response.json()['models']]
    except requests.exceptions.RequestException:
        return []


def get_best_model():
    """Get the best available model or default to 'llama2'."""
    available_models = get_available_models()
    return get_best_llama_model(available_models) or (available_models[0] if available_models else "llama2")


def chat_with_ollama(model: str, messages: list) -> str:
    """Interact with the Ollama model to generate a response."""
    url = "http://localhost:11434/api/chat"
    payload = {
        "model": model,
        "messages": messages,
        "stream": False,
    }
    headers = {"Content-Type": "application/json"}
    response = requests.post(url, data=json.dumps(payload), headers=headers)
    if response.status_code == 200:
        return response.json()['message']['content']
    else:
        return f"Error: {response.status_code}, {response.text}"


def render(todo):
    """Render a todo item."""
    tid = f'todo-{todo.id}'
    checkbox = Input(
        type="checkbox",
        name="english" if todo.done else None,
        checked=todo.done,
        hx_post=f"/toggle/{todo.id}",
        hx_swap="outerHTML",
    )
    delete = A(
        'Delete',
        hx_delete=f'/{todo.id}',
        hx_swap='outerHTML',
        hx_target=f"#{tid}",
    )
    return Li(
        checkbox,
        ' ',
        todo.title,
        ' | ',
        delete,
        id=tid,
        cls='done' if todo.done else '',
    )


def mk_input():
    """Create the chat input field."""
    return Input(
        id='msg',
        name='msg',
        placeholder='Type a message...',
        autofocus='autofocus',
    )


async def generate_and_stream_ai_response(prompt: str):
    """Generate and stream AI response to users."""
    response = await run_in_threadpool(
        chat_with_ollama,
        model,
        [{"role": "user", "content": prompt}],
    )
    words = response.split()
    for i in range(len(words)):
        partial_response = " ".join(words[: i + 1])
        for u in users.values():
            await u(
                Div(
                    f"Todo App: {partial_response}",
                    id='msg-list',
                    cls='fade-in',
                    style=MATRIX_STYLE,
                    _=f"this.scrollIntoView({{behavior: 'smooth'}});",
                )
            )
        await asyncio.sleep(0.05)  # Reduced delay for faster typing


async def quick_message(chatter: SimpleChatter, prompt: str):
    """Send a quick message to the chat interface."""
    response = await run_in_threadpool(
        chat_with_ollama,
        model,
        [{"role": "user", "content": prompt}],
    )
    words = response.split()
    for i in range(len(words)):
        partial_response = " ".join(words[: i + 1])
        await chatter.send(f"Todo App: {partial_response}")
        await asyncio.sleep(0.05)  # Adjust this delay as needed


def create_nav_menu(selected_chat="Chat Interface", selected_action="Actions"):
    """Create the navigation menu with chat and action dropdowns."""
    common_style = (
        "font-size: 1rem; height: 32px; line-height: 32px; "
        "display: inline-flex; align-items: center; justify-content: center; "
        "margin: 0 2px; border-radius: 16px; padding: 0 0.6rem;"
    )

    def create_menu_item(title, hx_get, summary_id):
        """Create a menu item."""
        return Li(
            A(
                title,
                hx_get=hx_get,
                hx_target=f"#{summary_id}",
                hx_swap="outerHTML",
                hx_trigger="click",
                hx_push_url="true",
                cls="menu-item",
            )
        )

    chat_summary_id = "chat-summary"
    action_summary_id = "action-summary"

    chat_menu = Details(
        Summary(
            selected_chat,
            style=(
                f"{common_style} width: {CHAT_INTERFACE_WIDTH}; "
                "background-color: var(--pico-background-color); "
                "border: 1px solid var(--pico-muted-border-color);"
            ),
            id=chat_summary_id,
        ),
        Ul(
            create_menu_item("Todo Chat", "/chat/todo_chat", chat_summary_id),
            create_menu_item("Future Chat 1", "/chat/future_chat_1", chat_summary_id),
            create_menu_item("Future Chat 2", "/chat/future_chat_2", chat_summary_id),
            create_menu_item("Future Chat 3", "/chat/future_chat_3", chat_summary_id),
            dir="rtl",
            id="chat-menu-list",
        ),
        cls="dropdown",
        id="chat-menu",
    )

    action_menu = Details(
        Summary(
            selected_action,
            style=(
                f"{common_style} width: {ACTIONS_WIDTH}; "
                "background-color: var(--pico-background-color); "
                "border: 1px solid var(--pico-muted-border-color);"
            ),
            id=action_summary_id,
        ),
        Ul(
            create_menu_item("Action 1", "/action/1", action_summary_id),
            create_menu_item("Action 2", "/action/2", action_summary_id),
            create_menu_item("Action 3", "/action/3", action_summary_id),
            create_menu_item("Action 4", "/action/4", action_summary_id),
            dir="rtl",
            id="action-menu-list",
        ),
        cls="dropdown",
        id="action-menu",
    )

    search_group = Group(
        Input(
            placeholder="Search",
            name="nav_input",
            id="nav-input",
            hx_post="/search",
            hx_trigger="keyup[keyCode==13]",
            hx_target="#msg-list",
            hx_swap="innerHTML",
            style=(
                f"{common_style} width: {SEARCH_WIDTH}; padding-right: 25px; "
                "border: 1px solid var(--pico-muted-border-color);"
            ),
        ),
        Button(
            "×",
            type="button",
            onclick="document.getElementById('nav-input').value = ''; this.blur();",
            style=(
                "position: absolute; right: 6px; top: 50%; transform: translateY(-50%); "
                "width: 16px; height: 16px; font-size: 0.8rem; color: var(--pico-muted-color); "
                "opacity: 0.5; background: none; border: none; cursor: pointer; padding: 0; "
                "display: flex; align-items: center; justify-content: center; "
                "border-radius: 50%;"
            ),
        ),
        style="display: flex; align-items: center; position: relative;",
    )

    nav = Div(
        chat_menu,
        action_menu,
        search_group,
        style="display: flex; align-items: center; gap: 8px;",
    )

    return nav


# Application Setup
app, rt, todos, Todo = fast_app(
    "data/todo.db",
    ws_hdr=True,
    live=True,
    render=render,
    id=int,
    title=str,
    done=bool,
    pk="id",
)

# Choose the best available model
model = get_best_model()

# WebSocket users
users = {}


def on_conn(ws, send):
    """Handle WebSocket connection."""
    users[str(id(ws))] = send


def on_disconn(ws):
    """Handle WebSocket disconnection."""
    users.pop(str(id(ws)), None)


# Route Handlers
@rt('/')
def get():
    """Handle the main page GET request."""
    nav = create_nav_menu()

    # Include the client-side script to close menus after selection
    script = Script(
        """
        document.body.addEventListener('htmx:afterSwap', function(evt) {
            if (evt.detail.target.id === 'chat-summary' || evt.detail.target.id === 'action-summary') {
                const detailsElement = evt.detail.target.closest('details');
                if (detailsElement) {
                    detailsElement.removeAttribute('open');
                    detailsElement.blur();
                }
            }
        });
        """
    )

    nav_group = Group(
        nav,
        style="display: flex; align-items: center; margin-bottom: 20px; gap: 20px;",
    )

    return Titled(
        "Pipulate Todo App",
        Container(
            nav_group,
            Grid(
                Div(
                    Card(
                        H2("Todo List"),
                        Ul(*[render(todo) for todo in todos()], id='todo-list'),
                        header=Form(
                            Group(
                                todo_mk_input(),
                                Button("Add", type="submit"),
                            ),
                            hx_post="/todo",
                            hx_swap="beforeend",
                            hx_target="#todo-list",
                        ),
                    ),
                ),
                Div(
                    Card(
                        H2("Chat Interface"),
                        Div(
                            id='msg-list',
                            cls='overflow-auto',
                            style='height: 40vh;',
                        ),
                        footer=Form(
                            Group(
                                mk_input(),
                                Button("Send", type='submit', ws_send=True),
                            )
                        ),
                    ),
                ),
                cls="grid",
                style="display: grid; grid-template-columns: 2fr 1fr; gap: 20px;",
            ),
            Div(
                A(
                    "Poke Todo List",
                    hx_post="/poke",
                    hx_target="#msg-list",
                    hx_swap="innerHTML",
                    cls="button",
                ),
                style="position: fixed; bottom: 20px; right: 20px; z-index: 1000;",
            ),
            script,  # Include the script here
        ),
        hx_ext='ws',
        ws_connect='/ws',
        data_theme="dark",
    )


@rt('/todo')
async def post_todo(todo: Todo):
    """Handle adding a new todo item."""
    inserted_todo = todos.insert(todo)

    # Adjusted prompt for brevity
    asyncio.create_task(
        generate_and_stream_ai_response(
            f"New todo: '{todo.title}'. Brief, sassy comment or advice in under 30 words."
        )
    )

    return render(inserted_todo), todo_mk_input()


@rt('/{tid}')
async def delete(tid: int):
    """Handle deleting a todo item."""
    todo = todos[tid]  # Get the todo item before deleting it
    todos.delete(tid)

    # Adjusted prompt for brevity
    asyncio.create_task(
        generate_and_stream_ai_response(
            f"Todo '{todo.title}' deleted. Brief, sassy reaction in under 30 words."
        )
    )

    return ''  # Return an empty string to remove the item from the DOM


@rt('/toggle/{tid}')
async def toggle(tid: int):
    """Handle toggling a todo item's done status."""
    todo = todos[tid]
    old_status = "Done" if todo.done else "Not Done"
    todo.done = not todo.done
    new_status = "Done" if todo.done else "Not Done"
    updated_todo = todos.update(todo)

    # Adjusted prompt for brevity
    asyncio.create_task(
        generate_and_stream_ai_response(
            f"Todo '{todo.title}' toggled from {old_status} to {new_status}. Brief, sassy comment in under 30 words."
        )
    )

    return Input(
        type="checkbox",
        name="english" if updated_todo.done else None,
        checked=updated_todo.done,
        hx_post=f"/toggle/{updated_todo.id}",
        hx_swap="outerHTML",
    )


@rt('/poke')
async def poke():
    """Handle poking the todo list for a response."""
    response = await run_in_threadpool(
        chat_with_ollama,
        model,
        [
            {
                "role": "system",
                "content": "You are a sassy Todo List. Respond briefly to being poked.",
            },
            {
                "role": "user",
                "content": "You've been poked. React in under 30 words.",
            },
        ],
    )
    return Div(f"Todo App: {response}", id='msg-list', cls='fade-in', style=MATRIX_STYLE)


@rt('/chat/{chat_type}')
async def chat_interface(chat_type: str):
    """Handle chat menu selection."""
    # Update the summary element with the selected chat type
    chat_summary_id = "chat-summary"
    selected_chat = chat_type.replace('_', ' ').title()
    summary_content = Summary(
        selected_chat,
        style=(
            f"font-size: 1rem; height: 32px; line-height: 32px; "
            "display: inline-flex; align-items: center; justify-content: center; "
            "margin: 0 2px; border-radius: 16px; padding: 0 0.6rem; "
            f"width: {CHAT_INTERFACE_WIDTH}; background-color: var(--pico-background-color); "
            "border: 1px solid var(--pico-muted-border-color);"
        ),
        id=chat_summary_id,
    )

    # Generate AI response
    prompt = f"You selected {selected_chat}. Briefly respond in character."
    chatter = SimpleChatter(
        send=lambda msg: asyncio.gather(
            *[
                u(
                    Div(
                        msg,
                        id='msg-list',
                        cls='fade-in',
                        style=MATRIX_STYLE,
                    )
                )
                for u in users.values()
            ]
        )
    )
    asyncio.create_task(quick_message(chatter, prompt))

    return summary_content


@rt('/action/{action_id}')
async def perform_action(action_id: str):
    """Handle action menu selection."""
    # Update the summary element with the selected action
    action_summary_id = "action-summary"
    selected_action = f"Action {action_id}"
    summary_content = Summary(
        selected_action,
        style=(
            f"font-size: 1rem; height: 32px; line-height: 32px; "
            "display: inline-flex; align-items: center; justify-content: center; "
            "margin: 0 2px; border-radius: 16px; padding: 0 0.6rem; "
            f"width: {ACTIONS_WIDTH}; background-color: var(--pico-background-color); "
            "border: 1px solid var(--pico-muted-border-color);"
        ),
        id=action_summary_id,
    )

    # Generate AI response
    prompt = f"You selected {selected_action}. Briefly respond in character."
    chatter = SimpleChatter(
        send=lambda msg: asyncio.gather(
            *[
                u(
                    Div(
                        msg,
                        id='msg-list',
                        cls='fade-in',
                        style=MATRIX_STYLE,
                    )
                )
                for u in users.values()
            ]
        )
    )
    asyncio.create_task(quick_message(chatter, prompt))

    return summary_content


@rt('/search', methods=['POST'])
async def search(nav_input: str):
    """Handle search input."""
    prompt = f"The user searched for: '{nav_input}'. Respond briefly acknowledging the search."
    chatter = SimpleChatter(
        send=lambda msg: asyncio.gather(
            *[
                u(
                    Div(
                        msg,
                        id='msg-list',
                        cls='fade-in',
                        style=MATRIX_STYLE,
                    )
                )
                for u in users.values()
            ]
        )
    )
    asyncio.create_task(quick_message(chatter, prompt))
    return ''


@rt('/toggle-theme', methods=['POST'])
def toggle_theme():
    """Handle theme toggle."""
    return ''  # Theme change is handled client-side


# WebSocket Handlers
@app.ws('/ws', conn=on_conn, disconn=on_disconn)
async def ws(msg: str):
    """Handle WebSocket messages."""
    if msg:
        global conversation
        conversation.append({"role": "user", "content": msg})

        # Send user message immediately with yellow color
        for u in users.values():
            await u(
                Div(
                    f"You: {msg}",
                    id='msg-list',
                    cls='fade-in',
                    style=USER_STYLE,
                )
            )

        # Start streaming response
        response = await run_in_threadpool(chat_with_ollama, model, conversation)
        conversation.append({"role": "assistant", "content": response})

        # Simulate typing effect (AI response remains green)
        words = response.split()
        for i in range(len(words)):
            partial_response = " ".join(words[: i + 1])
            for u in users.values():
                await u(
                    Div(
                        f"Todo App: {partial_response}",
                        id='msg-list',
                        cls='fade-in',
                        style=MATRIX_STYLE,
                        _=f"this.scrollIntoView({{behavior: 'smooth'}});",
                    )
                )
            await asyncio.sleep(0.05)  # Reduced delay for faster typing

        # Clear the input field after the response is complete and keep it focused
        clear_input = Input(
            id='msg',
            name='msg',
            placeholder='Type a message...',
            value='',
            hx_swap_oob="true",
            autofocus='autofocus',
        )
        for u in users.values():
            await u(clear_input)


# Start the application
if __name__ == "__main__":
    serve()