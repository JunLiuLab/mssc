library(Matrix)
library(Seurat)
library(data.table)
library(magrittr)
library(cowplot)
library(harmony)
library(uwot)
library(parallel)
exp.file <- list.files(path = "~/liulab_home/data/single_cell/GSE145281/", pattern = "*raw.txt.gz", full.names = T) %>%
  grep(pattern = "R[1-5]", value = T)
GSE145281.list <- lapply(exp.file, function(tt) {
  aa <- fread(tt)
  aa[, -1, with = F] %>%
    as.matrix() %>%
    t() %>%
    set_colnames(aa[[1]]) %>%
    Matrix(data = ., sparse = T) %>%
    list(exp = ., samples = rownames(.), genes = colnames(.))
})
GSE145281.exp.mat <- sapply(GSE145281.list, function(tt) tt$exp, simplify = F) %>%
  do.call(rbind, .)
GSE145281.meta <- lapply(seq(length(exp.file)), function(tt) {
  patient.curr <- basename(exp.file[[tt]]) %>%
    strsplit(x = ., split = "_") %>%
    unlist() %>%
    .[2]
  response <- substring(patient.curr, 1, 1) %>%
    equals("R") + 0
  data.table(samples = GSE145281.list[[tt]]$samples, patient = patient.curr, response = response)
}) %>% do.call(rbind, .)


gse145281 <- CreateSeuratObject(counts = t(GSE145281.exp.mat), project = "GSE145281", min.cells = 5) %>%
  Seurat::NormalizeData(verbose = FALSE) %>%
  FindVariableFeatures(selection.method = "vst", nfeatures = 2000) %>%
  ScaleData(verbose = FALSE) %>%
  RunPCA(pc.genes = pbmc@var.genes, npcs = 20, verbose = FALSE)
dir.create(".figs/gse145281")


GSE145281.meta.match <- GSE145281.meta[match(rownames(gse145281@meta.data), samples)]
gse145281@meta.data %<>% cbind(., GSE145281.meta.match[, .(patient, response)]) %>%
  as.data.frame()

set.seed(234512)
gse145281 <- gse145281 %>%
  RunHarmony("patient")


p1 <- DimPlot(object = gse145281, reduction = "harmony", pt.size = .1, group.by = "patient")
# p2 <- VlnPlot(object = gse145281, features = "harmony_1", group.by = "patient", do.return = TRUE, pt.size = .1)


gse145281 <- gse145281 %>%
  RunUMAP(reduction = "harmony", dims = 1:20) %>%
  FindNeighbors(reduction = "harmony", dims = 1:20) %>%
  FindClusters(resolution = 0.5) %>%
  identity()

p <- FeaturePlot(gse145281, features = c(
  "MS4A1", "GNLY", "CD3E", "CD14", "FCER1A", "FCGR3A", "LYZ", "PPBP",
  "CD8A", "GZMB", "PRF1", "IL7R", "CCR7", "CD4"
))
ggsave(plot = p, filename = ".figs/gse145281/feature.pdf")
DimPlot(gse145281, reduction = "umap", group.by = "patient", pt.size = .1, split.by = "patient") %>%
  ggsave(".figs/gse145281/gse145281.harmony.umap.patient.pdf", plot = .)

DimPlot(gse145281, reduction = "umap", group.by = "patient", label = TRUE, pt.size = .1) %>%
  ggsave(".figs/gse145281/gse145281.harmony.umap.pdf", plot = .)

DimPlot(gse145281, reduction = "umap", label = TRUE, pt.size = .1) %>%
  ggsave(".figs/gse145281/gse145281.harmony.umap.cluster.pdf", plot = .)

##


##

saveRDS(file = ".figs/gse145281/seurat.RDS", gse145281)
# Perform differntial expression using DESeq2
#' @export
DESeq2DETest <- function(
                         data.use,
                         cells.1,
                         cells.2,
                         verbose = TRUE,
                         ...) {
  # if (!PackageCheck('DESeq2', error = FALSE)) {
  #   stop("Please install DESeq2 - learn more at https://bioconductor.org/packages/release/bioc/html/DESeq2.html")
  # }
  group.info <- data.frame(row.names = c(cells.1, cells.2))
  group.info[cells.1, "group"] <- "Group1"
  group.info[cells.2, "group"] <- "Group2"
  group.info[, "group"] <- factor(x = group.info[, "group"])
  group.info$wellKey <- rownames(x = group.info)
  dds1 <- DESeq2::DESeqDataSetFromMatrix(
    countData = data.use,
    colData = group.info,
    design = ~group
  )
  dds1 <- DESeq2::estimateSizeFactors(object = dds1)
  dds1 <- DESeq2::estimateDispersions(object = dds1, fitType = "local")
  dds1 <- DESeq2::nbinomWaldTest(object = dds1)
  res <- DESeq2::results(
    object = dds1,
    contrast = c("group", "Group1", "Group2"),
    alpha = 0.05,
    ...
  )
  # to.return <- data.frame(p_val = res$pvalue, row.names = rownames(res))
  return(res)
}

## Implementation of psuedo-bulk method from : https://www.biorxiv.org/content/10.1101/2020.04.01.019851v1

# cluster 2 is cd8 cytotoxic t-cells
gse145281.clust <- gse145281[, gse145281$seurat_clusters == 2]
patient.cell.one.hot <- gse145281.clust@meta.data %>%
  data.table(ID = rownames(.)) %>%
  .[, .(ID, patient = as.factor(patient))] %>%
  .[, .(ID, patient)] %>%
  mltools::one_hot(.) %>%
  .[, -1, with = F] %>%
  as.matrix()

psuedo.bulk <- gse145281.clust@assays$RNA@counts %*% patient.cell.one.hot

cells.1 <- grep("_R", colnames(psuedo.bulk), value = T)
cells.2 <- grep("_NR", colnames(psuedo.bulk), value = T)
deseq.out <- DESeq2DETest(data.use = psuedo.bulk, cells.1 = cells.2, cells.2 = cells.1)
deseq.dt <- deseq.out %>%
  as.data.frame() %>%
  mutate(gene = rownames(.)) %>%
  data.table()
deseq.dt <- deseq.dt[order(padj)]
save(file = ".figs/gse145281/deseq.dt.RData", deseq.dt)
