import {useRef, forwardRef} from "react";

import {nextIndex, prevIndex, getEntries} from "../utils";

const List = forwardRef(function List({entries, index, visible, onValue}, ref) {
    if (!visible) {
        return null;
    }

    const itemClass = "cursor-pointer px-4 py-2";
    const inactiveClass = "text-gray-700 bg-white";
    const activeClass = "text-gray-900 bg-gray-200";
    const hoverClass = "hover:text-gray-900 hover:bg-gray-200";
    const style = {
        position: "absolute",
        left: 0,
        right: 0,
        top: "0.5rem",
        overflowY: "scroll"
    };
    const itemStyle = {display: "block"};
    const itemList = entries.map((x, i) => {
        const onClick = () => onValue(x.value);
        const baseClass = index === i ? activeClass : inactiveClass;
        const className = baseClass + ' ' + itemClass + ' ' + hoverClass;
        return <li id="list"
                className={className} role="menuitem" tabIndex="-1"
                style={itemStyle} onClick={onClick} key={x.key}>
            {x.key}
        </li>
    });
    const className = "border-2 border-gray-200 max-h-64";
    const list = <ul className={className} role="menu" style={style}>
        {itemList}
    </ul>;

    return <div ref={ref} style={{position: "relative"}}>{list}</div>;
});

export function textInputInitialState(props) {
    return {value: "", listVisible: false, index: -1}
}

export function TextInput({options, placeholder="", className="", state, setState}) {
    state = Object.assign({}, state);

    const ref = useRef(null);

    const entries = getEntries(state.value, options);

    function handleClick(v) {
        state.value = v;
        setState(state);
    }

    function handleInput(event) {
        state.value = event.target.value;
        setState(state);
    }

    function handleKeyDown(event) {
        switch (event.key) {
            case "ArrowDown":
                state.index = nextIndex(state.index, entries.length);
                setState(state);
                break;
            case "ArrowUp":
                event.preventDefault();
                state.index = prevIndex(state.index, entries.length);
                setState(state);
                break;
            case "Enter": case "Tab":
                if (state.index !== -1 && entries.length > 0) {
                    state.value = entries[state.index].value;
                    state.index = -1;
                    setState(state);
                }
                break;
            case "Escape":
                event.target.blur();
                break;
        }
    }

    function handleFocus() {
        state.listVisible = true;
        setState(state);
    }

    function handleBlur(event) {
        const tgt = event.relatedTarget;
        if (tgt && ref.current.contains(tgt)) {
            event.target.focus();
        } else {
            state.listVisible = false;
            setState(state);
        }
    }

    return <div className={className}>
        <input
         type="text" className="form-input w-full" placeholder={placeholder}
         onInput={handleInput} onKeyDown={handleKeyDown} onFocus={handleFocus}
         onBlur={handleBlur} value={state.value} />
        <List
         entries={entries} index={state.index} visible={state.listVisible}
         ref={ref} onValue={handleClick} />
    </div>;
}
