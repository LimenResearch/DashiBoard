# UI Guide

## Home screen

After opening the browser at the starting page (see [Getting Started](@ref)),
you will be greeted by the following page.

![UI home page](assets/home.png)

## Loading data

To load data, simply select one or more files from the "Choose files" dropdown.

You will have access to all the files available in you data directory, provided
that their format is supported. See also [`DataIngestion.is_supported`](@ref).

![UI file selection](assets/load.png)

Upon pressing the `Load` button, the data is loaded in the `Source` table,
displayed on the top right.

![loaded data](assets/loaded.png)

## Filtering data

The `Filter` tab allows users to filter their data.
At the moment, we support checkboxes for categorical columns and min / max
selectors for continuous ones.

Upon clicking on `Submit`, the filtered data is loaded in the `Selection` table,
displayed on the bottom right.

![filtered data](assets/filtered.png)

## Processing data

Data is processed via cards, small building blocks that add new columns to the 
filtered data.

To add a new card, click on the `＋` and select the type of card you wish to add.

![launching the new card selection menu](assets/new-card-0.png)

![choosing the new card](assets/new-card-1.png)

![the new card is generated](assets/new-card-1.png)

You can add and compile as many cards as you wish.

Upon clicking on `Submit`, the additional columns are added to the `Selection` table.

![processed data](assets/processed.png)
