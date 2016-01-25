SphinxSearch builder
====================

This image acts as builder for the **SphinxSearch** docker images.

It's purpose is to download and to install SphinxSearch and its dependencies, then it compiles sources in order to create an exportable bundle.

Options
-------

The builder takes several options:

| **Parameter**  | **Explaination**                                               |
| -------------- | -------------------------------------------------------------- |
| `-r <release>` | The version of SphinxSearch for which to build a docker image. |
