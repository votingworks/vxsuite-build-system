When using public Debian repos, there can be multiple high-level repos, e.g. `main`, `non-free-firmware`. Now that we are using VxWorks self-hosted repos, we create a single `main` repo with all packages contained within it, regardless of their public source. As a result, this can cause our COTS report playbook to generate broken links for packages originally located outside of `main`. 

After generating a COTS report, you can run the [scripts/tb-validate-cots-report.sh](https://github.com/votingworks/vxsuite-build-system/blob/main/scripts/tb-validate-cots-report.sh) script. It will notify you of any broken links within the report. At this time, manual intervention is required to fix these links.

As an example, we will use a sample broken link for the `firmware-sof-signed` package.
```
http://snapshot.debian.org/archive/debian/20241031T212645Z/pool/main/f/firmware-sof/firmware-sof-signed_2.2.4-1_all.deb = 404
```

The first step is to look this package up on snapshot.debian.org and determine the correct "pool" to use. 

1. Navigate to [snapshot.debian.org](https://snapshot.debian.org)
2. Search for the package name (no versions) using the "Search for a binary package name" input field. In our example, you would search for `firmware-sof-signed`
3. On the results page, find the specific version and select it. In this example: `2.2.4-1`
4. In the `Binary packages` section, you will see references to the package, along with information about where the package is available. You're looking for something like "Seen in debian on 2023-01-21 21:34:39 in /pool/non-free-firmware/f/firmware-sof."
5. Make note of the value immediately after `/pool/`. That is what you need to modify in the COTS report. In our example, that value is `non-free-firmware`, so you would change `main` to `non-free-firmware`. Everything else should remain the same. The updated link would be:
```
http://snapshot.debian.org/archive/debian/20241031T212645Z/pool/non-free-firmware/f/firmware-sof/firmware-sof-signed_2.2.4-1_all.deb
```
6. After updating all broken links, you should run the validation script again to verify all links are now valid. Once they are, your COTS report should be ready for further use. 
