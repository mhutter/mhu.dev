---
date: 2016-02-17T13:37:00+01:00
title: Crontab Syntax
summary: A quick tutorial on the Crontab scheduling syntax
tags: [cron]
---

One thing I still cannot remember after YEARS of usage is the scheduling syntax for cronjobs. To help with this I usually paste the following into each crontab:

```plain
# m h dom mon dow cmd
```

- `m`: minute
- `h`: hour
- `dom`: day of month
- `mon`: month
- `dow`: day of week
- `cmd`: command to execute


## Expressions

Instead of fixed numbers, you can also use expressions. You probably already know the **asterisk** (`*`) to match _every value_, but there are more:

- use **commas** to specify a _list of values_, eg. `2,5,7`
- use **hyphens** to specify a _range of values_, eg. `5-9`
- use **slashes** to specify _steps_, eg. `*/2` in the minute field to execute a command every other minute. (note: `*/2` in the minute field means _execute command on every minute divisible by 2_)
