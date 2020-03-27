# AWS Jenkins images

These JSON files are used to build images for Jenkins builders in AWS. Build
these images with [Packer]:

```
packer.io validate fedora-31.json
packer.io build fedora-31.json
```

[Packer]: https://packer.io/
