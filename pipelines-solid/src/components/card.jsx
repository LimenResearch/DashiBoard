import { PercentilePartition, initPercentilePartition } from "../cards/percentile-partition"

const CARD_DICT = new Map();

CARD_DICT.set(
    "Percentile Partition",
    {init: initPercentilePartition, component: PercentilePartition}
);

export function initCard(props) {
    return CARD_DICT().get(props.name).init();
}

export function Card(props) {

    const children = CARD_DICT.get(props.name).component(props);

    return <div class="bg-white w-full p-4 mb-4">
        <span class="text-blue-800 text-2xl font-semibold">{props.name}</span>
        <span onClick={props.onClose}
            class="text-red-800 hover:text-red-900 text-2xl font-semibold float-right cursor-pointer">
            ✕
        </span>
        <div class="mt-2">
        {children}
        </div>
    </div>
}
