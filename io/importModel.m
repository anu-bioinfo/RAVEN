function model=importModel(fileName,removeExcMets,isCOBRA,supressWarnings)
% importModel
%   Import a constraint-based model from a SBML file
%
%   fileName        a SBML file to import
%   removeExcMets   true if exchange metabolites should be removed. This is
%                   needed to be able to run simulations, but it could also 
%                   be done using simplifyModel at a later stage (opt,
%                   default true)
%   isCOBRA         true if the SBML-file is a COBRA Toolbox file (opt, default
%                   false)
%   supressWarnings true if warnings regarding the model structure should
%                   be supressed (opt, default false)
%
%   model
%       description      description of model contents
%       id               model ID
%       rxns             reaction ids
%       mets             metabolite ids
%       S                stoichiometric matrix
%       lb               lower bounds
%       ub               upper bounds
%       rev              reversibility vector
%       c                objective coefficients
%       b                equality constraints for the metabolite equations
%       comps            compartment ids
%       compNames        compartment names
%       compOutside      the id (as in comps) for the compartment
%                        surrounding each of the compartments
%       compMiriams      structure with MIRIAM information about the
%                        compartments
%       rxnNames         reaction description
%       rxnComps         compartments for reactions
%       grRules          reaction to gene rules in text form
%       rxnGeneMat       reaction-to-gene mapping in sparse matrix form
%       subSystems       subsystem name for each reaction
%       eccodes          EC-codes for the reactions
%       rxnMiriams       structure with MIRIAM information about the reactions
%       genes            list of all genes
%       geneComps        compartments for reactions
%       geneMiriams      structure with MIRIAM information about the genes
%       metNames         metabolite description
%       metComps         compartments for metabolites
%       inchis           InChI-codes for metabolites
%       metFormulas      metabolite chemical formula
%       metMiriams       structure with MIRIAM information about the metabolites
%       unconstrained    true if the metabolite is an exchange metabolite
%
%   Loads models in the COBRA Toolbox format and in the format used in
%   the yeast consensus reconstruction. The resulting structure is compatible
%   with COBRA Toolbox. A number of consistency checks are performed in order
%   to ensure that the model is valid. Take these warnings seriously and modify the
%   model structure to solve them. The RAVEN Toolbox is made to function
%   only on consistent models, and the only checks performed are when the
%   model is imported. You can use exportToExcelFormat, modify the model in
%   Microsoft Excel and then reimport it using importExcelModel (or remake
%   the SBML file using SBMLFromExcel)
%
%   NOTE: This script requires that libSBML is installed.
%   
%   NOTE: All IDs are assumed to be named C_, M_, E_, R_ for compartments, 
%         metabolites, genes, and reactions. This is true for models
%         generated by SBMLFromExcel and those that follow the yeast
%         consensus network model formulation.
%
%   Usage: model=importModel(fileName,removeExcMets,isCOBRA,supressWarnings)
%
%   Rasmus Agren, 2013-08-06
%

if nargin<2
    removeExcMets=true;
end

if nargin<3
    isCOBRA=false;
end

if nargin<4
    supressWarnings=false;
end

%This is to match the order of the fields to those you get from importing
%from Excel
model=[];
model.description=[];
model.id=[];
model.annotation=[];
model.rxns={};
model.mets={};
model.S=[];
model.lb=[];
model.ub=[];
model.rev=[];
model.c=[];
model.b=[];
model.comps={};
model.compNames={};
model.compOutside={};
model.compMiriams={};
model.rxnNames={};
model.rxnComps=[];
model.grRules={};
model.rxnGeneMat=[];
model.subSystems={};
model.eccodes={};
model.rxnMiriams={};
model.genes={};
model.geneComps=[];
model.geneMiriams={};
model.metNames={};
model.metComps=[];
model.inchis={};
model.metFormulas={};
model.metMiriams={};
model.unconstrained=[];

%Load the model using libSBML
modelSBML = TranslateSBML(fileName);

if isempty(modelSBML)
   dispEM('There is a problem with the SBML file. Try using the SBML Validator at http://sbml.org/Facilities/Validator');
end

%Retrieve compartment names and IDs
compartmentNames=cell(numel(modelSBML.compartment),1);
compartmentIDs=cell(numel(modelSBML.compartment),1);
compartmentOutside=cell(numel(modelSBML.compartment),1);
compartmentMiriams=cell(numel(modelSBML.compartment),1);

for i=1:numel(modelSBML.compartment)
    compartmentNames{i}=modelSBML.compartment(i).name;
    if isCOBRA==true
		try strcmpi(modelSBML.compartment(i).id(1:2),'C_')
			compartmentIDs{i}=modelSBML.compartment(i).id(3:end);
        catch
			compartmentIDs{i}=modelSBML.compartment(i).id;
		end
    else
        compartmentIDs{i}=modelSBML.compartment(i).id(3:end);
    end
    if isfield(modelSBML.compartment(i),'outside')
        if ~isempty(modelSBML.compartment(i).outside)
            if isCOBRA==true
				if strcmpi(modelSBML.compartment(i).outside(1:2),'C_')
					compartmentOutside{i}=modelSBML.compartment(i).outside(3:end);
				else
					compartmentOutside{i}=modelSBML.compartment(i).outside;
				end
            else
                compartmentOutside{i}=modelSBML.compartment(i).outside(3:end);
            end
        else
            compartmentOutside{i}='';
        end
    else
        compartmentOutside{i}=[];
    end
    
    if isfield(modelSBML.compartment(i),'annotation')
        compartmentMiriams{i}=parseMiriam(modelSBML.compartment(i).annotation);
    else
        compartmentMiriams{i}=[];
    end
end

%If there are no compartment names then use compartment id as name
if all(cellfun(@isempty,compartmentNames))
    compartmentNames=compartmentIDs;
end

%Retrieve info on metabolites, genes, complexes
metaboliteNames={};
metaboliteIDs={};
metaboliteCompartments={};
metaboliteUnconstrained=[];
metaboliteFormula={};
metaboliteInChI={};
metaboliteMiriams={};

geneNames={};
geneIDs={};
geneMiriams={};
geneShortNames={};
geneCompartments={};
complexIDs={};
complexNames={};

%If the file is not a COBRA Toolbox model. According to the format
%specified in the yeast consensus model both metabolites and genes are a
%type of 'species'. The metabolites have names starting with 'M_' and genes
%with 'E_'.
if isCOBRA==false
    for i=1:numel(modelSBML.species) 
        if strcmpi(modelSBML.species(i).id(1:2),'M_')
            metaboliteNames{numel(metaboliteNames)+1,1}=modelSBML.species(i).name;
            metaboliteIDs{numel(metaboliteIDs)+1,1}=modelSBML.species(i).id(3:end);
            metaboliteCompartments{numel(metaboliteCompartments)+1,1}=modelSBML.species(i).compartment(3:end);
            metaboliteUnconstrained(numel(metaboliteUnconstrained)+1,1)=modelSBML.species(i).boundaryCondition;

            %For each metabolite retrieve the formula and the InChI code if
            %available
            %First add the InChI code and the formula from the InChI. This
            %allows for overwriting the formula by setting the actual formula
            %field
            if ~isempty(modelSBML.species(i).annotation)
                %Get the formula if available
                startString='>InChI=';
                endString='</in:inchi>';
                formStart=strfind(modelSBML.species(i).annotation,startString);
                if ~isempty(formStart)
                    formEnd=strfind(modelSBML.species(i).annotation,endString);
                    formEndIndex=find(formEnd>formStart, 1 );
                    formula=modelSBML.species(i).annotation(formStart+numel(startString):formEnd(formEndIndex)-1);
                    metaboliteInChI{numel(metaboliteInChI)+1,1}=formula;

                    %The composition is most often present between the first
                    %and second "/" in the model. In some simple molecules,
                    %such as salts, there is no second "/". The formula is then
                    %assumed to be to the end of the string
                    compositionIndexes=strfind(formula,'/');
                    if numel(compositionIndexes)>1
                        metaboliteFormula{numel(metaboliteFormula)+1,1}=...
                            formula(compositionIndexes(1)+1:compositionIndexes(2)-1);
                    else
                        if numel(compositionIndexes)==1
                            %Probably a simple molecule which can have only one
                            %conformation
                            metaboliteFormula{numel(metaboliteFormula)+1,1}=...
                            formula(compositionIndexes(1)+1:numel(formula));
                        else
                            metaboliteFormula{numel(metaboliteFormula)+1,1}='';
                        end
                    end
                else
                    metaboliteInChI{numel(metaboliteInChI)+1,1}='';
                    metaboliteFormula{numel(metaboliteFormula)+1,1}='';
                end
                
                %Get Miriam info
                metMiriam=parseMiriam(modelSBML.species(i).annotation);
                metaboliteMiriams{numel(metaboliteMiriams)+1,1}=metMiriam;
            else
                metaboliteInChI{numel(metaboliteInChI)+1,1}='';
                metaboliteFormula{numel(metaboliteFormula)+1,1}='';
                metaboliteMiriams{numel(metaboliteMiriams)+1,1}=[];
            end

            if ~isempty(modelSBML.species(i).notes)
                %Get the formula if available
                startString='FORMULA:';
                endString='</';
                formStart=strfind(modelSBML.species(i).notes,startString);
                if ~isempty(formStart)
                    formEnd=strfind(modelSBML.species(i).notes,endString);
                    formEndIndex=find(formEnd>formStart, 1 );
                    formula=strtrim(modelSBML.species(i).notes(formStart+numel(startString):formEnd(formEndIndex)-1));
                    metaboliteFormula{numel(metaboliteFormula),1}=formula;
                end
            end
        end

        if strcmpi(modelSBML.species(i).id(1:2),'E_')
            geneNames{numel(geneNames)+1,1}=modelSBML.species(i).name;
            
            %The "E_" is included in the ID. This is because it's only used
            %internally in this file and it makes the matching a little
            %smoother
            geneIDs{numel(geneIDs)+1,1}=modelSBML.species(i).id;
            geneCompartments{numel(geneCompartments)+1,1}=modelSBML.species(i).compartment(3:end);

            %Get Miriam structure
            if isfield(modelSBML.species(i),'annotation')
                %Get Miriam info
                geneMiriam=parseMiriam(modelSBML.species(i).annotation);
                geneMiriams{numel(geneMiriams)+1,1}=geneMiriam;
            else
                geneMiriams{numel(geneMiriams)+1,1}=[];
            end
            
            %Protein short names (for example ERG10) are saved as SHORT
            %NAME: NAME in the notes-section of metabolites for the "new
            %format" and as PROTEIN_ASSOCIATION for each reaction in COBRA
            %Toolbox format. For now only the SHORT NAME is loaded, and no
            %mapping takes place
            if ~isempty(modelSBML.species(i).notes)
                %Get the short name if available
                startString='SHORT NAME:';
                endString='</';
                shortStart=strfind(modelSBML.species(i).notes,startString);
                if ~isempty(shortStart)
                    shortEnd=strfind(modelSBML.species(i).notes,endString);
                    shortEndIndex=find(shortEnd>shortStart, 1 );
                    shortName=strtrim(modelSBML.species(i).notes(shortStart+numel(startString):shortEnd(shortEndIndex)-1));
                    geneShortNames{numel(geneShortNames)+1,1}=shortName;
                else
                    geneShortNames{numel(geneShortNames)+1,1}='';
                end
            else
                geneShortNames{numel(geneShortNames)+1,1}='';
            end
        end
        
        %If it's a complex keep the ID and name
        if strcmpi(modelSBML.species(i).id(1:3),'Cx_')
            complexIDs=[complexIDs;modelSBML.species(i).id];
            complexNames=[complexNames;modelSBML.species(i).name];
        end        
    end
    
%If it's a COBRA Toolbox file
else
    for i=1:numel(modelSBML.species) 
        %The metabolite names are assumed to be M_NAME_COMPOSITION or
        %_NAME_COMPOSITION or NAME_COMPOSITION or NAME
        underscoreIndex=strfind(modelSBML.species(i).name,'_');

        %Skip the first character if it's an underscore
        if any(underscoreIndex)
            if underscoreIndex(1)==1
                metaboliteNames{numel(metaboliteNames)+1,1}=modelSBML.species(i).name(2:max(underscoreIndex)-1);
            else
                %If the second character is an underscore than check if the
                %first is "M".
                if underscoreIndex(1)==2
                    if modelSBML.species(i).name(1)=='M'
                        metaboliteNames{numel(metaboliteNames)+1,1}=modelSBML.species(i).name(3:max(underscoreIndex)-1);
                    else
                        %If not, then use the full name
                        metaboliteNames{numel(metaboliteNames)+1,1}=modelSBML.species(i).name(1:max(underscoreIndex)-1);
                    end
                else
                    %Use the full name
                    metaboliteNames{numel(metaboliteNames)+1,1}=modelSBML.species(i).name(1:max(underscoreIndex)-1);
                end
            end
        else
            %Use the full name
            metaboliteNames{numel(metaboliteNames)+1,1}=modelSBML.species(i).name;
        end
        
        metaboliteIDs{numel(metaboliteIDs)+1,1}=modelSBML.species(i).id(3:numel(modelSBML.species(i).id));
		try strcmpi(modelSBML.species(i).compartment(1:2),'C_')
			metaboliteCompartments{numel(metaboliteCompartments)+1,1}=modelSBML.species(i).compartment(3:end);
        catch
			metaboliteCompartments{numel(metaboliteCompartments)+1,1}=modelSBML.species(i).compartment;
		end
		
        %I think that COBRA doesn't set the boundary condition, but rather
        %uses name_b. Check for either
        metaboliteUnconstrained(numel(metaboliteUnconstrained)+1,1)=modelSBML.species(i).boundaryCondition;
        if strcmp(metaboliteIDs{end}(max(end-1,1):end),'_b')
            metaboliteUnconstrained(end)=1;
        end
        
        %Get the formula
        if max(underscoreIndex)<length(modelSBML.species(i).name)
            metaboliteFormula{numel(metaboliteFormula)+1,1}=modelSBML.species(i).name(max(underscoreIndex)+1:length(modelSBML.species(i).name));
        else
            metaboliteFormula{numel(metaboliteFormula)+1,1}='';
        end
        
        %The newer COBRA version sometimes has composition information in
        %the notes instead
        if ~isempty(modelSBML.species(i).notes)
            %Get the formula if available
            startString='FORMULA:';
            endString='</';
            formStart=strfind(modelSBML.species(i).notes,startString);
            if ~isempty(formStart)
                formEnd=strfind(modelSBML.species(i).notes,endString);
                formEndIndex=find(formEnd>formStart, 1 );
                formula=strtrim(modelSBML.species(i).notes(formStart+numel(startString):formEnd(formEndIndex)-1));
                metaboliteFormula{numel(metaboliteFormula),1}=formula;
            end
        end
    end
end

%Retrieve info on reactions
reactionNames=cell(numel(modelSBML.reaction),1);
reactionIDs=cell(numel(modelSBML.reaction),1);
subsystems=cell(numel(modelSBML.reaction),1);
subsystems(:,:)=cellstr('');
eccodes=cell(numel(modelSBML.reaction),1);
eccodes(:,:)=cellstr('');
grRules=cell(numel(modelSBML.reaction),1);
grRules(:,:)=cellstr('');
rxnComps=zeros(numel(modelSBML.reaction),1);
rxnMiriams=cell(numel(modelSBML.reaction),1);
reactionReversibility=zeros(numel(modelSBML.reaction),1);
reactionUB=zeros(numel(modelSBML.reaction),1);
reactionLB=zeros(numel(modelSBML.reaction),1);
reactionObjective=zeros(numel(modelSBML.reaction),1);

%Construct the stoichiometric matrix while the reaction info is read
S=zeros(numel(metaboliteIDs),numel(modelSBML.reaction));

%This is for collecting all genes before getting a unique list (only used
%in the COBRA format). The reason is to avoid too many calls to strmatch
tempGeneList={};

counter=0;
for i=1:numel(modelSBML.reaction)
    
    %Check that the reaction doesn't produce a complex and nothing else.
    %If so, then jump to the next reaction. This is because I get the
    %genes for complexes from the names and not from the reactions that
    %create them. This only applies to the non-COBRA format.
    if numel(modelSBML.reaction(i).product)==1
        if strcmp(modelSBML.reaction(i).product(1).species(1:3),'Cx_')==true
        	continue;
        end
    end
    
    %It didn't look like a gene complex-forming reaction
    counter=counter+1;
    
    if isCOBRA && numel(modelSBML.reaction(i).name)>2
        %In COBRA the reaction names starts with "R_" but I check to be
        %sure
        if strcmp(modelSBML.reaction(i).name(1:2),'R_')
            reactionNames{counter}=modelSBML.reaction(i).name(3:end);
        else
            reactionNames{counter}=modelSBML.reaction(i).name;
        end
    else
        reactionNames{counter}=modelSBML.reaction(i).name;
    end
    
    %Assumes that the ID starts with "R_"
    reactionIDs{counter}=modelSBML.reaction(i).id(3:end);
    reactionReversibility(counter)=modelSBML.reaction(i).reversible;
    
    %The order of these parameters should not be hard coded
    if isfield(modelSBML.reaction(i).kineticLaw,'parameter')
        reactionLB(counter)=modelSBML.reaction(i).kineticLaw.parameter(1).value;
        reactionUB(counter)=modelSBML.reaction(i).kineticLaw.parameter(2).value;
        reactionObjective(counter)=modelSBML.reaction(i).kineticLaw.parameter(3).value;
    else
        if reactionReversibility(counter)==true
            reactionLB(counter)=-inf;
        else
            reactionLB(counter)=0;
        end
        reactionUB(counter)=inf;
        reactionObjective(counter)=0;
    end
    
    %Find the associated gene if available
    if isCOBRA==false
        if isfield(modelSBML.reaction(i),'modifier')
            if ~isempty(modelSBML.reaction(i).modifier)
                rules='';
                for j=1:numel(modelSBML.reaction(i).modifier)
                    modifier=modelSBML.reaction(i).modifier(j).species;
                    if ~isempty(modifier)
                        if strfind(modifier,'E_')
                            index=find(strcmp(modifier,geneIDs));
                            %This should be unique and in the geneIDs list, otherwise
                            %something is wrong
                            if numel(index)~=1
                               dispEM(['Could not get the gene association data from reaction ' reactionIDs{i}]); 
                            end
                            %Add the association
                            %rxnGeneMat(i,index)=1;
                            if ~isempty(rules)
                                rules=[rules ' or (' geneNames{index} ')'];
                            else
                                rules=['(' geneNames{index} ')'];
                            end
                        else
                           %It seems to be a complex. Add the corresponding
                           %genes from the name of the complex (not the
                           %reaction that creates it)
                           index=find(strcmp(modifier,complexIDs));
                           if numel(index)==1
                               if ~isempty(rules)
                                    rules=[rules ' or (' strrep(complexNames{index},':',' and ') ')'];
                                else
                                    rules=['(' strrep(complexNames{index},':',' and ') ')'];
                               end
                           else
                              %Could not find a complex
                              dispEM(['Could not get the gene association data from reaction ' reactionIDs{i}]);
                           end
                        end
                    end
                end
                grRules{counter}=rules;
            end
        end
    else
        %Get gene association for COBRA Toolbox models. The genes are added
        %here as well as the associations. Gene complexes are ok, but only
        %if they are on the form (A and B and...)       
        if ~isempty(modelSBML.reaction(i).notes)
            startString='GENE_ASSOCIATION:';
            endString='</';
            geneStart=strfind(modelSBML.reaction(i).notes,startString);
            if isempty(geneStart)
                startString='GENE ASSOCIATION:';
                geneStart=strfind(modelSBML.reaction(i).notes,startString);
            end
            if ~isempty(geneStart)
                geneEnd=strfind(modelSBML.reaction(i).notes,endString);
                geneEndIndex=find(geneEnd>geneStart, 1 );
                geneAssociation=strtrim(modelSBML.reaction(i).notes(geneStart+numel(startString):geneEnd(geneEndIndex)-1));          
                if ~isempty(geneAssociation)
                    %This adds the grRules. The gene list and rxnGeneMat
                    %are created later
                    grRules{counter}=geneAssociation;
                end
            end
        end
    end
    
    %Add subsystems and reaction compartment
    if ~isempty(modelSBML.reaction(i).notes)
        %Get the subsystem if available
        startString='SUBSYSTEM:';
        endString='</';
        subStart=strfind(modelSBML.reaction(i).notes,startString);
        if ~isempty(subStart)
            subEnd=strfind(modelSBML.reaction(i).notes,endString);
            subEndIndex=find(subEnd>subStart, 1 );
            subsystem=strtrim(modelSBML.reaction(i).notes(subStart+numel(startString):subEnd(subEndIndex)-1));
            subsystems{counter}=subsystem;
        end
        startString='COMPARTMENT:';
        endString='</';
        compStart=strfind(modelSBML.reaction(i).notes,startString);
        if ~isempty(compStart)
            compEnd=strfind(modelSBML.reaction(i).notes,endString);
            compEndIndex=find(compEnd>compStart, 1 );
            rxnComp=strtrim(modelSBML.reaction(i).notes(compStart+numel(startString):compEnd(compEndIndex)-1));
            %Find it in the compartment list
            [crap J]=ismember(rxnComp,compartmentIDs);
            rxnComps(counter)=J;
        end
    end
    
    %Get ec-codes
    flagEmpty=false;
    if isCOBRA==false
        if ~isempty(modelSBML.reaction(i).annotation)
            searchString=modelSBML.reaction(i).annotation;
            startString='urn:miriam:ec-code:';
            endString='"';
        else
            flagEmpty=true;
        end
    else
        if ~isempty(modelSBML.reaction(i).notes)
            searchString=modelSBML.reaction(i).notes;
            startString='PROTEIN_CLASS:';
            endString='</';
        else
            flagEmpty=true;
        end
    end
    
    if flagEmpty==false
        ecStart=strfind(searchString,startString);
        ecEnd=strfind(searchString,endString);
        %There can be several ec-codes, but they should be merged to one
        %string
        for j=1:numel(ecStart)
            ecEndIndex=find(ecEnd>ecStart(j), 1 );
            eccode=strtrim(searchString(ecStart(j)+numel(startString):ecEnd(ecEndIndex)-1));
            if j==1
                eccodes{counter}=eccode;
            else
                eccodes{counter}=[eccodes{counter} ';' eccode];
            end
        end
    end 
 
    %Get other Miriam fields. This may include for example database indexes
    %to organism-specific databases. EC-codes are supported by the COBRA
    %Toolbox format and are therefore loaded separately
    if isCOBRA==false
        miriamStruct=parseMiriam(modelSBML.reaction(i).annotation);
        rxnMiriams{counter}=miriamStruct; 
    end
    
    %Add all reactants
    for j=1:numel(modelSBML.reaction(i).reactant)
       %Get the index of the metabolite in metaboliteIDs. External 
       %metabolites will be removed at a later stage
       %Assumes that all metabolites start with "M_"
       metIndex=find(strcmp(modelSBML.reaction(i).reactant(j).species(3:end),metaboliteIDs),1);
       if isempty(metIndex)
            dispEM(['Could not find metabolite ' modelSBML.reaction(i).reactant(j).species(3:end) ' in reaction ' reactionIDs{counter}]); 
       end
       S(metIndex,counter)=S(metIndex,counter)+modelSBML.reaction(i).reactant(j).stoichiometry*-1;
    end
    
    %Add all products
    for j=1:numel(modelSBML.reaction(i).product)
       %Get the index of the metabolite in metaboliteIDs.
       %Assumes that all metabolites start with "M_"
       metIndex=find(strcmp(modelSBML.reaction(i).product(j).species(3:end),metaboliteIDs),1);
       if isempty(metIndex)
            dispEM(['Could not find metabolite ' modelSBML.reaction(i).reactant(j).species(3:end) ' in reaction ' reactionIDs{counter}]); 
       end
       S(metIndex,counter)=S(metIndex,counter)+modelSBML.reaction(i).product(j).stoichiometry;
    end
end

%Shrink the structures if complex-forming reactions had to be skipped
reactionNames=reactionNames(1:counter);
reactionIDs=reactionIDs(1:counter);
subsystems=subsystems(1:counter);
eccodes=eccodes(1:counter);
grRules=grRules(1:counter);
rxnMiriams=rxnMiriams(1:counter);
reactionReversibility=reactionReversibility(1:counter);
reactionUB=reactionUB(1:counter);
reactionLB=reactionLB(1:counter);
reactionObjective=reactionObjective(1:counter);
S=S(:,1:counter);

model.description=modelSBML.name;
model.id=modelSBML.id;
model.rxns=reactionIDs;
model.mets=metaboliteIDs;
model.S=sparse(S);
model.lb=reactionLB;
model.ub=reactionUB;
model.rev=reactionReversibility;
model.c=reactionObjective;
model.b=zeros(numel(metaboliteIDs),1);
model.comps=compartmentIDs;
model.compNames=compartmentNames;

%Load annotation if available
if isfield(modelSBML,'annotation')
    endString='</';
    I=strfind(modelSBML.annotation,endString);
    J=strfind(modelSBML.annotation,'<vCard:Family>');
    if any(J)
       model.annotation.familyName=modelSBML.annotation(J+14:I(find(I>J,1))-1);
    end
    J=strfind(modelSBML.annotation,'<vCard:Given>');
    if any(J)
       model.annotation.givenName=modelSBML.annotation(J+13:I(find(I>J,1))-1);
    end
    J=strfind(modelSBML.annotation,'<vCard:EMAIL>');
    if any(J)
       model.annotation.email=modelSBML.annotation(J+13:I(find(I>J,1))-1);
    end
    J=strfind(modelSBML.annotation,'<vCard:Orgname>');
    if any(J)
       model.annotation.organization=modelSBML.annotation(J+15:I(find(I>J,1))-1);
    end
    endString='"/>';
    I=strfind(modelSBML.annotation,endString);
    J=strfind(modelSBML.annotation,'"urn:miriam:');
    if any(J)
       model.annotation.taxonomy=modelSBML.annotation(J+12:I(find(I>J,1))-1);
    end
end
if isfield(modelSBML,'notes')
    startString=strfind(modelSBML.notes,'xhtml">');
    endString=strfind(modelSBML.notes,'</body>');
    if any(startString) && any(endString)
       model.annotation.note=modelSBML.notes(startString+7:endString-1);
    end
end

if any(~cellfun(@isempty,compartmentOutside))
    model.compOutside=compartmentOutside;
end

model.rxnNames=reactionNames;
model.metNames=metaboliteNames;

%Match the compartments for metabolites
[I J]=ismember(metaboliteCompartments,model.comps);
model.metComps=J;

%If any genes have been loaded (only for the new format)
if ~isempty(geneNames)
    model.genes=geneNames;
    model.rxnGeneMat=getGeneMat(grRules,geneNames);
    model.grRules=grRules;
    %Match the compartments for genes
    [I J]=ismember(geneCompartments,model.comps);
    model.geneComps=J;
else
    if ~isempty(grRules)
       grRules=strrep(grRules,' AND ',' and ');
       grRules=strrep(grRules,' OR ',' or ');
       %In the non-COBRA version genes are surrounded by parenthesis even
       %if they are the only gene. Also, only single spaces are used
       %between genes. I'm pretty sure this is compatible with COBRA Toolbox so I
       %change it to be the same here.
       grRules=strrep(grRules,'  ',' ');
       grRules=strrep(grRules,'((','(');
       grRules=strrep(grRules,'))',')');
       grRules=strrep(grRules,'( ','(');
       grRules=strrep(grRules,' )',')');
       grRules=strrep(grRules,') or (','*%%%%*');
       grRules=strrep(grRules,' or ',') or (');
       grRules=strrep(grRules,'*%%%%*',') or (');
       
       %Not very neat, but add parenthesis if missing
       for i=1:numel(grRules)
          if any(grRules{i})
              if ~strcmp(grRules{i}(1),'(')
                  grRules{i}=['(' grRules{i} ')'];
              end
          end
       end
       [rxnGeneMat, genes]=getGeneMat(grRules);
       model.rxnGeneMat=rxnGeneMat;
       model.genes=genes;
       model.grRules=grRules;
    end
end

%If any InChIs have been loaded
if any(~cellfun(@isempty,metaboliteInChI))
    model.inchis=metaboliteInChI;
end

%If any formulas have been loaded
if any(~cellfun(@isempty,metaboliteFormula))
    model.metFormulas=metaboliteFormula;
end

%If any gene short names have been loaded
if any(~cellfun(@isempty,geneShortNames))
    model.geneShortNames=geneShortNames;
end

%If any Miriam strings for compartments have been loaded
if any(~cellfun(@isempty,compartmentMiriams))
    model.compMiriams=compartmentMiriams;
end

%If any Miriam strings for metabolites have been loaded
if any(~cellfun(@isempty,metaboliteMiriams))
    model.metMiriams=metaboliteMiriams;
end

%If any subsystems have been loaded
if any(~cellfun(@isempty,subsystems))
    model.subSystems=subsystems;
end
if any(rxnComps)
   if all(rxnComps)
       model.rxnComps=rxnComps;
   else
       if supressWarnings==false
            dispEM('The compartments for the following reactions could not be matched. Ignoring reaction compartment information',false,model.rxns(rxnComps==0));
       end
   end
end

%If any ec-codes have been loaded
if any(~cellfun(@isempty,eccodes))
    model.eccodes=eccodes;
end

%If any Miriam strings for reactions have been loaded
if any(~cellfun(@isempty,rxnMiriams))
    model.rxnMiriams=rxnMiriams;
end

%If any Miriam strings for genes have been loaded
if any(~cellfun(@isempty,geneMiriams))
    model.geneMiriams=geneMiriams;
end

model.unconstrained=metaboliteUnconstrained;

%Remove unused fields
if isempty(model.annotation)
    model=rmfield(model,'annotation');
end
if isempty(model.compOutside)
    model=rmfield(model,'compOutside');
end
if isempty(model.compMiriams)
    model=rmfield(model,'compMiriams');
end
if isempty(model.rxnComps)
    model=rmfield(model,'rxnComps');
end
if isempty(model.grRules)
    model=rmfield(model,'grRules');
end
if isempty(model.rxnGeneMat)
    model=rmfield(model,'rxnGeneMat');
end
if isempty(model.subSystems)
    model=rmfield(model,'subSystems');
end
if isempty(model.eccodes)
    model=rmfield(model,'eccodes');
end
if isempty(model.rxnMiriams)
    model=rmfield(model,'rxnMiriams');
end
if isempty(model.genes)
    model=rmfield(model,'genes');
end
if isempty(model.geneComps)
    model=rmfield(model,'geneComps');
end
if isempty(model.geneMiriams)
    model=rmfield(model,'geneMiriams');
end
if isempty(model.inchis)
    model=rmfield(model,'inchis');
end
if isempty(model.metFormulas)
    model=rmfield(model,'metFormulas');
end
if isempty(model.metMiriams)
    model=rmfield(model,'metMiriams');
end

%This just removes the grRules if no genes have been loaded
if ~isfield(model,'genes') && isfield(model,'grRules')
   model=rmfield(model,'grRules'); 
end

%Print warnings about bad structure
if supressWarnings==false
    checkModelStruct(model,false);
end

if removeExcMets==true
    model=simplifyModel(model);
end
end

function [rxnGeneMat, matchGenes]=getGeneMat(grRules,matchGenes)
%Constructs the rxnGeneMat matrix and the cell array with gene names from
%the grRules. Uses the genes in the order defined by matchGenes if supplied. No
%checks are made here since that should have been made before.

if nargin<2
    matchGenes={};
end

%Assume that everything that isn't a paranthesis, " AND " or " or " is a
%gene name
genes=strrep(grRules,'(','');
genes=strrep(genes,')','');
genes=strrep(genes,' or ',' ');
genes=strrep(genes,' and ',' ');
[crap crap crap crap crap crap genes]=regexp(genes,' ');

if isempty(matchGenes)
    allNames={};
    for i=1:numel(genes)
        allNames=[allNames genes{i}];
    end
    matchGenes=unique(allNames)';
    
    %Remove the empty element if present
    if isempty(matchGenes{1})
        matchGenes(1)=[];
    end
end

%Create the matrix
rxnGeneMat=zeros(numel(genes),numel(matchGenes));

for i=1:numel(genes)
    if ~isempty(genes{i})
        for j=1:numel(genes{i})
            if ~isempty(genes{i}{j})
                index=find(strcmp(genes{i}{j},matchGenes));
                if numel(index)==1
                    rxnGeneMat(i,index)=1;
                else
                    dispEM(['The gene ' genes{i}{j} ' could not be matched to a gene in the gene list.']); 
                end
            end
        end
    end
end
rxnGeneMat=sparse(rxnGeneMat);
end

function miriamStruct=parseMiriam(searchString)
%Gets the names and values of Miriam-string. Nothing fancy at all, just to
%prevent using the same code for metabolites, genes, and reactions

if ~isempty(searchString)	
    startString='urn:miriam:';
	midString=':';
	endString='"';
    startIndexes=strfind(searchString,startString);
    midIndexes=strfind(searchString,midString);
    endIndexes=strfind(searchString,endString);
    miriamStruct=[];

    if ~isempty(startIndexes)
        counter=0;
        for j=1:numel(startIndexes)
            endIndex=find(endIndexes>startIndexes(j)+numel(startString), 1 );
            
            midIndex=find(midIndexes>startIndexes(j)+numel(startString) & midIndexes<endIndexes(endIndex),1);
            
            %It was like this before and I don't understand why!
            %midIndex=find(midIndexes<endIndexes(endIndex),1,'last');
            
            miriam=searchString(startIndexes(j)+numel(startString):midIndexes(midIndex)-1);

            %Construct the struct
            if ~strcmpi(miriam,'ec-code')
                counter=counter+1;
                miriamStruct.name{counter,1}=miriam;
                if any(midIndex)
                    miriamStruct.value{counter,1}=searchString(midIndexes(midIndex)+1:endIndexes(endIndex)-1);
                else
                    %This is if there is no miriam type defined, but that
                    %there still is some value defined
                    miriamStruct.value{counter,1}=searchString(startIndexes(j)+numel(startString):endIndexes(endIndex)-1);
                end
            end
        end
    end
else
    miriamStruct=[];
end
end